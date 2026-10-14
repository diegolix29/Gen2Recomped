"""Offline desktop translation worker. Downloads models, never uploads text."""
import argparse, json, os, re, shutil, sys, tempfile, urllib.request, zipfile
import ctypes, hashlib, threading
GPU_WARMUP_SECONDS = 60
from pathlib import Path
INDEX = "https://raw.githubusercontent.com/argosopentech/argospm-index/main/index.json"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

def emit(**event):
    print(json.dumps(event, ensure_ascii=False), flush=True)

CUDA_HANDLES = []
def prepare_cuda(request):
    if os.name != "nt":
        return
    root = Path(request["models"]) / "cuda"
    names = ["cublasLt64_12.dll", "cublas64_12.dll"]
    if not all((root / name).is_file() for name in names):
        # a CUDA 12 install on the system already has it: no download
        try:
            CUDA_HANDLES.extend(ctypes.WinDLL(name) for name in names)
            return
        except OSError:
            pass
    # "auto" fetches it too: an NVIDIA card is the whole reason the GPU path
    # was chosen, and without cuBLAS that card cannot run a single batch --
    # auto used to announce the GPU and then hang on the first one
    if request.get("hardware", "auto") in ("gpu", "auto") and not all((root / name).is_file() for name in names):
        root.mkdir(parents=True, exist_ok=True)
        emit(kind="status", phase="download", message="Finding NVIDIA GPU support (one-time download)")
        with urllib.request.urlopen("https://pypi.org/pypi/nvidia-cublas-cu12/12.6.4.1/json", timeout=30) as response:
            metadata = json.load(response)
        wheel = next(item for item in metadata["urls"] if item["filename"].endswith("win_amd64.whl"))
        archive = root / "cublas.whl"
        # the package and the two libraries it holds are on disk together for
        # a moment: ~435 MB + ~640 MB.  Said up front, not discovered as a
        # truncated download -- a full C: drive left a 155 MB .part behind and
        # GPU mode quietly fell back to the CPU every time.
        needed = int(wheel.get("size") or 450_000_000) + 700_000_000
        free = shutil.disk_usage(root).free
        if free < needed:
            raise OSError("not enough disk space for NVIDIA GPU support: needs %.1f GB free on %s, has %.1f GB"
                          % (needed / 1e9, root.anchor or root, free / 1e9))
        try:
            fetch(wheel["url"], archive, message="Downloading NVIDIA GPU support")
        finally:
            archive.with_suffix(archive.suffix + ".part").unlink(missing_ok=True)
        digest = hashlib.sha256()
        with archive.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != wheel["digests"]["sha256"]:
            archive.unlink(missing_ok=True)
            raise ValueError("GPU library checksum mismatch")
        try:
            with zipfile.ZipFile(archive) as package:
                for name in names:
                    member = next(item for item in package.infolist() if item.filename.endswith("/" + name))
                    try:
                        with package.open(member) as source, (root / (name + ".part")).open("wb") as output:
                            shutil.copyfileobj(source, output)
                    except BaseException:
                        (root / (name + ".part")).unlink(missing_ok=True)
                        raise
                    (root / (name + ".part")).replace(root / name)
                for member in package.infolist():
                    if Path(member.filename).name.upper().startswith("LICENSE"):
                        (root / "NVIDIA-LICENSE.txt").write_bytes(package.read(member))
        finally:
            archive.unlink(missing_ok=True)
    if all((root / name).is_file() for name in names):
        os.environ["PATH"] = str(root.resolve()) + os.pathsep + os.environ.get("PATH", "")
        CUDA_HANDLES.extend(ctypes.WinDLL(str((root / name).resolve())) for name in names)

def cublas_loadable(request):
    """True when cuBLAS can actually be loaded -- ours or the system's.

    A CUDA device being present is not enough: ctranslate2 loads cuBLAS lazily
    on the FIRST BATCH, and when it is missing the native library aborts or
    hangs there, after "Using NVIDIA GPU" has already been reported -- the
    launcher then sits on that line forever.  Asked up front, a missing
    library is a quiet fall back to the CPU instead."""
    if os.name != "nt":
        return True
    root = Path(request["models"]) / "cuda"
    for name in ("cublasLt64_12.dll", "cublas64_12.dll"):
        candidate = root / name
        try:
            CUDA_HANDLES.append(ctypes.WinDLL(str(candidate.resolve()) if candidate.is_file() else name))
        except OSError:
            return False
    return True

def make_engine(ctranslate2, path, request, force_cpu=False):
    hardware = request.get("hardware", "auto")
    if not force_cpu and hardware != "cpu":
        try:
            if ctranslate2.get_cuda_device_count() > 0:
                prepare_cuda(request)
                if not cublas_loadable(request):
                    raise RuntimeError("NVIDIA cuBLAS could not be installed or loaded")
                engine = ctranslate2.Translator(str(path), device="cuda", compute_type="int8_float16")
                # prove it before announcing it: one tiny batch on the GPU, on a
                # watchdog -- a native hang inside CUDA cannot be caught, and
                # it left the launcher on "Using NVIDIA GPU" indefinitely
                outcome = {}
                def warm():
                    try:
                        engine.translate_batch([["▁a"]], beam_size=1, max_decoding_length=4)
                        outcome["ok"] = True
                    except Exception as warm_error:
                        outcome["error"] = warm_error
                probe = threading.Thread(target=warm, daemon=True)
                probe.start()
                probe.join(GPU_WARMUP_SECONDS)
                if "error" in outcome:
                    raise outcome["error"]
                if not outcome.get("ok"):
                    raise RuntimeError("GPU did not respond within %d seconds" % GPU_WARMUP_SECONDS)
                emit(kind="status", phase="load", message="Using NVIDIA GPU for translation")
                return engine, "cuda"
        except Exception as error:
            emit(kind="status", phase="load", message="GPU unavailable; using CPU: " + str(error).splitlines()[0])
    threads = max(1, min(8, (os.cpu_count() or 2) // 2))
    engine = ctranslate2.Translator(str(path), device="cpu", compute_type="int8", intra_threads=threads)
    emit(kind="status", phase="load", message=f"Using CPU for translation ({threads} threads)")
    return engine, "cpu"

def fetch(url, dest, phase="download", message="Downloading translation model"):
    if not url.startswith("https://"):
        raise ValueError("Model downloads require HTTPS")
    dest.parent.mkdir(parents=True, exist_ok=True)
    pending = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=60) as response, pending.open("wb") as output:
        total = int(response.headers.get("Content-Length", 0) or 0)
        done = 0
        last = 0
        import time
        emit(kind="progress", phase=phase, message=message, done=0, total=total, unit="bytes")
        while True:
            chunk = response.read(256 * 1024)
            if not chunk:
                break
            output.write(chunk)
            done += len(chunk)
            if time.monotonic() - last >= 0.2:
                emit(kind="progress", phase=phase, message=message, done=done, total=total, unit="bytes")
                last = time.monotonic()
        emit(kind="progress", phase=phase, message=message, done=done, total=total, unit="bytes")
    pending.replace(dest)

def install_model(root, source, target):
    dest = root / (source + "-" + target)
    if (dest / "model" / "model.bin").is_file():
        return dest
    emit(kind="status", phase="download", message="Finding translation model: " + source + " → " + target)
    with urllib.request.urlopen(INDEX, timeout=30) as response:
        packages = json.load(response)
    candidates = [p for p in packages if p["from_code"] == source and p["to_code"] == target]
    if not candidates:
        raise RuntimeError("No offline model for " + source + " -> " + target)
    def version(p):
        return tuple(int(n) for n in re.findall(r"\d+", p.get("package_version", "0")))
    selected = max(candidates, key=version)
    links = [url for url in selected["links"] if url.startswith("https://")]
    if not links:
        raise RuntimeError("No HTTPS model download available")
    root.mkdir(parents=True, exist_ok=True)
    archive = root / (source + "-" + target + ".argosmodel")
    candidates = links + [url.replace("https://argos-net.com/v1/", "https://data.argosopentech.com/argospm/v1/") for url in links if url.startswith("https://argos-net.com/v1/")]
    error = None
    for url in candidates:
        try:
            fetch(url, archive, message="Downloading model: " + source + " → " + target)
            error = None
            break
        except Exception as failure:
            error = failure
    if error:
        raise error
    staging = Path(tempfile.mkdtemp(prefix="unpack-", dir=root))
    emit(kind="status", phase="install", message="Installing translation model")
    try:
        with zipfile.ZipFile(archive) as package:
            if sum(i.file_size for i in package.infolist()) > 1024 * 1024 * 1024:
                raise ValueError("Translation model is too large")
            for member in package.infolist():
                path = (staging / member.filename).resolve()
                if not path.is_relative_to(staging.resolve()):
                    raise ValueError("Invalid model archive path")
            package.extractall(staging)
        metadata = next(staging.rglob("metadata.json"))
        info = json.loads(metadata.read_text(encoding="utf-8"))
        if info["from_code"] != source or info["to_code"] != target:
            raise ValueError("Model language does not match requested pair")
        if dest.exists():
            shutil.rmtree(dest)
        metadata.parent.replace(dest)
        return dest
    finally:
        shutil.rmtree(staging, ignore_errors=True)
        archive.unlink(missing_ok=True)

def translate(request):
    import ctranslate2
    import sentencepiece
    source, target = request["source"], request["target"]
    if not re.fullmatch(r"[a-z]{2,3}", source) or not re.fullmatch(r"[a-z]{2,3}", target):
        raise ValueError("Invalid language code")
    texts = request["texts"]
    if request.get("font"):
        font = Path(request["fonts"]) / request["font"]
        if not font.is_file():
            emit(kind="status", message="Downloading language font")
            fetch(request["fontUrl"], font, phase="font", message="Downloading language font")
    if not texts or source == target:
        return texts
    root = Path(request["models"])
    stages = [(source, target)] if source == "en" or target == "en" else [(source, "en"), ("en", target)]
    for stage, (from_code, to_code) in enumerate(stages):
        path = install_model(root, from_code, to_code)
        tokenizer = path / "sentencepiece.model"
        if not tokenizer.is_file():
            raise RuntimeError("Model tokenizer is unsupported")
        emit(kind="status", phase="load", message="Loading offline translation model")
        processor = sentencepiece.SentencePieceProcessor(model_file=str(tokenizer))
        engine, device = make_engine(ctranslate2, path / "model", request)
        metadata = json.loads((path / "metadata.json").read_text(encoding="utf-8"))
        prefix = metadata.get("target_prefix", "")
        result = []
        batch_size = 128 if device == "cuda" else 32
        emit(kind="progress", phase="translate", message="Translating game text", done=stage * len(texts), total=len(stages) * len(texts), unit="segments")
        for start in range(0, len(texts), batch_size):
            batch = texts[start:start + batch_size]
            tokens = [processor.encode(text, out_type=str) for text in batch]
            kwargs = {"target_prefix": [processor.encode(prefix, out_type=str)] * len(batch)} if prefix else {}
            try:
                outputs = engine.translate_batch(tokens, beam_size=2, max_batch_size=1024,
                    batch_type="tokens", max_decoding_length=512, **kwargs)
            except RuntimeError:
                if device != "cuda":
                    raise
                del engine
                emit(kind="status", phase="load", message="GPU could not translate this batch; continuing on CPU")
                engine, device = make_engine(ctranslate2, path / "model", request, force_cpu=True)
                outputs = engine.translate_batch(tokens, beam_size=2, max_batch_size=512,
                    batch_type="tokens", max_decoding_length=512, **kwargs)
            for output in outputs:
                text = processor.decode_pieces(output.hypotheses[0]).replace("\u2581", " ").replace("_", " ").strip()
                if prefix and text.startswith(prefix):
                    text = text[len(prefix):].lstrip()
                result.append(text)
            emit(kind="progress", phase="translate", message="Translating game text", done=stage * len(texts) + len(result), total=len(stages) * len(texts), unit="segments")
        texts = result
        del engine
    return texts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
        emit(kind="done", translations=translate(request))
    except Exception as error:
        emit(kind="error", message=str(error))
        return 1
    return 0

if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    # exit hard: a GPU probe that hung is still parked in native code, and an
    # ordinary exit would wait on it (or on CUDA teardown) forever
    os._exit(code)
