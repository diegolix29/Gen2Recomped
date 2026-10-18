import os,subprocess,tempfile,shutil
from pathlib import Path
bash=Path(shutil.which('git')).parent.parent/'bin/bash.exe' if os.name=='nt' else Path(shutil.which('bash'))
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'clients.lua'
 env={k:v for k,v in os.environ.items() if not k.startswith(('GOOGLE_','MICROSOFT_'))};env['CI']='true'
 # Bash accepts Windows paths on this host. Never read or print live credentials.
 def run():return subprocess.run([str(bash),'scripts/write_cloud_clients.sh',out.as_posix()],env=env,capture_output=True,text=True)
 r=run();assert r.returncode!=0 and not out.exists(),(r.returncode,r.stderr)
 env['CI']='false';out.write_text('preserved-config');r=run();assert r.returncode==0 and out.read_text()=='preserved-config',(r.returncode,r.stderr)
 env['GOOGLE_DEVICE_CLIENT_ID']='fake-client';env['GOOGLE_DEVICE_CLIENT_SECRET']='fake-secret';r=run();assert r.returncode==0 and 'fake-client' in out.read_text(),(r.returncode,r.stderr)
 env['GOOGLE_DEVICE_CLIENT_ID']='bad\nclient';r=run();assert r.returncode!=0
 print('Cloud build configuration checks: 4 passed')
