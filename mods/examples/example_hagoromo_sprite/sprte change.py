from PIL import Image

def rearrange_sprite_sheet(input_path, output_path):
    # Load the original 1x6 sprite sheet
    try:
        img = Image.open(input_path)
    except FileNotFoundError:
        print(f"Error: Could not find '{input_path}'.")
        return

    width, height = img.size

    # Calculate individual frame dimensions (assuming 6 equal vertical frames)
    frame_width = width
    frame_height = height // 6

    # Create a new blank image for the 2x3 layout
    # Using 'RGBA' to preserve transparency if you ever switch to PNGs
    new_img = Image.new('RGB', (frame_width * 2, frame_height * 3))

    # Loop through all 6 frames and reposition them
    for i in range(6):
        # New grid coordinates (2 columns, 3 rows)
        col = i % 2
        row = i // 2
        
        # Crop the current frame from the original vertical strip
        left = 0
        upper = i * frame_height
        right = frame_width
        lower = (i + 1) * frame_height
        frame = img.crop((left, upper, right, lower))
        
        # Calculate paste coordinates for the new image
        paste_x = col * frame_width
        paste_y = row * frame_height
        
        # Paste the frame into the 2x3 grid
        new_img.paste(frame, (paste_x, paste_y))

    # Save the result
    new_img.save(output_path)
    print(f"Success! Saved new 2x3 sprite sheet as '{output_path}'.")

# Run the conversion
rearrange_sprite_sheet("hagoromo_sprite.png", "hagoromo_sprite_2x3.png")