import argparse
import serial


PAGE_SIZE: int = 256
START_SEQUENCE: str = "KAMP"


def load_hex_file(filename: str) -> bytes:
    with open(filename, "r") as file:
        content: str = "".join(file.read().split())
    
    content_bytes: bytes = bytes.fromhex(content)

    if len(content_bytes) % PAGE_SIZE != 0:
        content_bytes += bytes(PAGE_SIZE - len(content_bytes) % PAGE_SIZE);

    return content_bytes


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-p", "--port",
        required=True,
        help="Serial port name",
        type=str
    )
    parser.add_argument(
        "-b", "--baud",
        required=False,
        help="Serial port baud rate",
        type=int,
        default=115200
    )
    parser.add_argument(
        "--start-page",
        required=False,
        help="Page number to start programming from",
        type=int,
        default=0
    )
    parser.add_argument(
        "hexfile",
        help="Hex file name",
        type=str
    )

    args = parser.parse_args()

    content = load_hex_file(args.hexfile)
    
    with serial.Serial(args.port, args.baud, timeout=5) as ser:
        total_pages = len(content) // PAGE_SIZE

        print(f"Flashing {total_pages} pages")

        for i in range(total_pages):
            erase_now = i % 16 == 0
            erase_char = ("1" if erase_now else "0").encode("ascii")

            if erase_now:
                print(f"Erasing sector {i // 16} (pages {i} to {i + 15})")

            page = args.start_page + i
            page_start_addr = page * 256

            frame = bytearray()
            frame += START_SEQUENCE.encode("ascii")
            frame += page_start_addr.to_bytes(3, "big")
            frame += erase_char
            frame += content[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]

            ser.write(frame)
            ser.flush()

            ack = ser.read(1)

            if ack == b"\xDD":
                print(f"Page {page} verification failed")
                break
            elif ack == b"\xAA":
                print(f"Page {page} verification successful")
            else:
                print(f"No ACK for page {page}")
                break

            print(f"Page {page} flashed")

    print("Done.")


if __name__ == "__main__":
    main() 
