import os
import sys
from enum import Enum

class TILE(Enum):
    SPIDER_WEB = 0x03
    DIAMOND_BRICK = 0x04
    STONE_BRICK = 0x06
    CUBE_INV = 0x08

tile_to_idx_map = {
    TILE.SPIDER_WEB.value: 0,
    TILE.DIAMOND_BRICK.value: 1,
    TILE.STONE_BRICK.value: 2,
    TILE.CUBE_INV.value: 3
}

def combine_tiles(tile1, tile2, tile3, tile4):
    """Combine four tile values into a single byte."""
    combined_byte = (tile1 << 6) | (tile2 << 4) | (tile3 << 2) | tile4
    return combined_byte

def package_bytes(bytes, width, height):
    """Package tile bytes into compressed format."""
    packaged_byte_list = []
    blocks_per_row = width // 2  # Number of 2x2 tile blocks in a row

    for row in range(0, height, 2):  # Correctly step through rows for 2x2 blocks
        for col in range(0, blocks_per_row):  # No need to step by 2 here
            # Correct index calculation for the 2x2 block
            idx1 = (row * width) + (col * 2)
            idx2 = idx1 + 1
            idx3 = idx1 + width
            idx4 = idx3 + 1

            # Assuming 'bytes' is a list of numeric tile identifiers
            tile_values = [tile_to_idx_map.get(bytes[idx], 0) for idx in [idx1, idx2, idx3, idx4]]

            packaged_byte = combine_tiles(*tile_values)
            packaged_byte_list.append(packaged_byte)

    return packaged_byte_list


def read_bytes(file_name, file_size):
    """Read bytes from a binary file."""
    with open(file_name, "rb") as file:
        file_bytes = file.read(file_size)
    return bytearray(file_bytes)

def write_bytes(file_name, bytes_data):
    """Write bytes to a binary file."""
    with open(file_name, "wb") as file:
        file.write(bytes_data)

def main():
    # Assume the binary file name is passed as the first argument
    binary_file_name = sys.argv[1]
    binary_file_size = os.stat(binary_file_name).st_size
    tile_bytes = read_bytes(binary_file_name, binary_file_size)
    
    # Example usage with a predefined width
    width = 32  # This needs to be set based on your actual tile map width
    packaged_bytes = bytearray(package_bytes(tile_bytes,30, width))
    
    # write_bytes(binary_file_name.replace(".bin", "_compressed.bin"), packaged_bytes)
    print(packaged_bytes)

if __name__ == "__main__":
    main()
