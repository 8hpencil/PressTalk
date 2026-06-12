import os
import sys
import subprocess
from PIL import Image, ImageDraw

def make_background_transparent(img_path, output_path):
    print("Making background transparent using flood-fill from corners...")
    img = Image.open(img_path).convert("RGBA")
    width, height = img.size
    
    # Create a binary mask where 255 indicates a white-ish pixel
    mask = Image.new("L", (width, height), 0)
    img_data = img.load()
    mask_data = mask.load()
    
    for y in range(height):
        for x in range(width):
            r, g, b, _ = img_data[x, y]
            # Threshold for white-ish background
            if r > 240 and g > 240 and b > 240:
                mask_data[x, y] = 255
                
    # Flood-fill from the four corners in the mask to mark the connected background as 128
    ImageDraw.floodfill(mask, (0, 0), 128)
    ImageDraw.floodfill(mask, (width - 1, 0), 128)
    ImageDraw.floodfill(mask, (0, height - 1), 128)
    ImageDraw.floodfill(mask, (width - 1, height - 1), 128)
    
    # Update the alpha channel of the original image based on the floodfilled mask
    mask_data = mask.load()
    for y in range(height):
        for x in range(width):
            if mask_data[x, y] == 128:
                r, g, b, _ = img_data[x, y]
                img_data[x, y] = (r, g, b, 0)
                
    img.save(output_path, "PNG")
    print("Transparent PNG saved to:", output_path)

def create_iconset(png_path, iconset_dir):
    print("Creating iconset directories and resizing images...")
    os.makedirs(iconset_dir, exist_ok=True)
    img = Image.open(png_path)
    
    sizes = [
        ("16x16", 16),
        ("16x16@2x", 32),
        ("32x32", 32),
        ("32x32@2x", 64),
        ("128x128", 128),
        ("128x128@2x", 256),
        ("256x256", 256),
        ("256x256@2x", 512),
        ("512x512", 512),
        ("512x512@2x", 1024)
    ]
    
    for name, size in sizes:
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized_path = os.path.join(iconset_dir, f"icon_{name}.png")
        resized.save(resized_path)
        
    print("Iconset created successfully.")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 process_icon.py <path_to_generated_png>")
        sys.exit(1)
        
    src_png = sys.argv[1]
    temp_png = "temp_transparent_icon.png"
    iconset_dir = "AppIcon.iconset"
    icns_name = "AppIcon.icns"
    
    # 1. Make background transparent
    make_background_transparent(src_png, temp_png)
    
    # 2. Create iconset
    create_iconset(temp_png, iconset_dir)
    
    # 3. Compile to .icns using iconutil
    print("Compiling iconset to AppIcon.icns using iconutil...")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir], check=True)
    
    # 4. Cleanup temporary files
    print("Cleaning up temporary files...")
    if os.path.exists(temp_png):
        os.remove(temp_png)
    for f in os.listdir(iconset_dir):
        os.remove(os.path.join(iconset_dir, f))
    os.rmdir(iconset_dir)
    
    print(f"Successfully generated macOS app icon: {icns_name}")

if __name__ == "__main__":
    main()
