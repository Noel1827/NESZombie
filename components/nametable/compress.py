import os
import sys
from enum import Enum

class StageTwoTiles(Enum):
    """ Enum representing various tiles specific to stage two. """
    SPIDERWEB = 0x22
    DIAMOND = 0x24
    STONE = 0x26
    EMPTY = 0x08

# Mapping of tile hexadecimal values to simpler numeric indices
tile_index_map = {
    StageTwoTiles.SPIDERWEB.value: 0,
    StageTwoTiles.DIAMOND.value: 1,
    StageTwoTiles.STONE.value: 2,
    StageTwoTiles.EMPTY.value: 3
}

def main():
    file_path = sys.argv[1]
    file_size = os.path.getsize(file_path)
    file_content = read_binary_file(file_path, file_size)
    
    attribute_data = extract_footer(file_content, 64)
    compressed_tiles = compress_tile_data(file_content)
    
    write_binary_data(f"{file_path[:-4]}_right_compressed.bin", compressed_tiles)
    write_binary_data(f"{file_path[:-4]}_right_attributes.bin", attribute_data)

def read_binary_file(path, size) -> bytearray:
    """ Load binary data from file up to a specified size. """
    with open(path, "rb") as file:
        return bytearray(file.read(size))

def extract_footer(data, num_bytes):
    """ Extracts a specific number of bytes from the end of a data array. """
    return data[-num_bytes:]

def compress_tile_data(data):
    """ Compresses tile data into a compact format for storage or transmission. """
    tiles_per_row = 16  # Derived from full row width divided by 2
    compressed_data = []

    for row in range(0, 30, 2):  # Assumes 30 total rows, iterating by two
        for col in range(0, tiles_per_row, 4):  # Process every four 2-tile blocks per row
            base_idx = (row * 32) + (col * 2)
            tile_values = [data[base_idx + offset] for offset in [0, 2, 4, 6]]
            compressed_byte = pack_tiles_into_byte(tile_values)
            compressed_data.append(compressed_byte)

    return bytearray(compressed_data)

def pack_tiles_into_byte(tile_indices):
    """ Packs four 2-bit tile indices into a single byte. """
    return sum(tile << (6 - 2*i) for i, tile in enumerate(tile_indices))

def write_binary_data(filename, bytes_data):
    """ Writes byte data to a specified file in binary mode. """
    with open(filename, "wb") as file:
        file.write(bytes_data)

if __name__ == "__main__":
    main()
