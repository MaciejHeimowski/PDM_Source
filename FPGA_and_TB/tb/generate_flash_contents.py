import random

NUM_LINES = 65536
OUTPUT_FILE = "tb/flash_contents.hex"

with open(OUTPUT_FILE, "w") as f:
    for _ in range(NUM_LINES):
        f.write(f"{random.randint(0, 255):02X}\n")

print(f"Generated {NUM_LINES} lines in {OUTPUT_FILE}")
