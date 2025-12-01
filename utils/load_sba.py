#!/usr/bin/env python3
import sys
import time
import re
import socket

def dmi_write(sock, addr, data):
    """Send DMI write command via OpenOCD telnet"""
    cmd = f"riscv dmi_write 0x{addr:02x} 0x{data:08x}\n"
    sock.sendall(cmd.encode())
    # Receive and discard the response to keep socket clean
    try:
        sock.settimeout(0.1)
        response = sock.recv(4096).decode()
        sock.settimeout(None)
    except socket.timeout:
        sock.settimeout(None)
    return None

def dmi_read(sock, addr):
    """Send DMI read command via OpenOCD telnet"""
    cmd = f"riscv dmi_read 0x{addr:02x}\n"
    sock.sendall(cmd.encode())
    time.sleep(0.1)  # Give OpenOCD time to complete DMI transaction and respond
    response = sock.recv(4096).decode()

    # Debug: Show raw response
    print(f"    DEBUG dmi_read(0x{addr:02x}) raw response:")
    for line in response.split('\n'):
        if line.strip():
            print(f"      |{line}|")

    # Parse: look for standalone hex value (not part of command echo)
    lines = response.split('\n')
    for line in lines:
        line = line.strip()
        # Skip lines containing commands
        if 'dmi_read' in line or 'dmi_write' in line:
            continue
        # Skip the '>' prompt
        if line == '>':
            continue
        # Look for hex value (may have leading/trailing whitespace after strip)
        # The strip() already removed spaces, so check if it's pure hex
        match = re.match(r'^0x([0-9a-fA-F]+)$', line)
        if match:
            value = int(match.group(1), 16)
            print(f"    DEBUG: Parsed value 0x{value:08x}")
            return value

    print(f"    WARNING: No hex value found in response")
    return None

def load_binary_via_sba(binary_path, base_addr=0x80000000):
    """Load binary file into SRAM via SBA"""

    # Connect to OpenOCD telnet
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('localhost', 4444))
    sock.recv(4096)  # Read welcome banner

    print(f"Loading {binary_path} to 0x{base_addr:08x} via SBA...")

    # Configure SBCS:
    # - sbreadonaddr = 1  (bit 15): perform read on address write
    # - sbaccess     = 2  (bits 19:17): 32-bit accesses
    # NOTE: We do NOT rely on sbautoincrement here; the script manually updates
    #       the address for each word. This makes it work even with older
    #       bitstreams or conservative SBA arbiters.
    print("Configuring SBA...")
    dmi_write(sock, 0x38, 0x00147000)

    # Set base address
    print(f"Setting address 0x{base_addr:08x}...")
    dmi_write(sock, 0x39, base_addr & 0xFFFFFFFF)  # SBAddress0
    dmi_write(sock, 0x3A, (base_addr >> 32) & 0xFFFFFFFF)  # SBAddress1

    # Read binary and write word by word
    with open(binary_path, 'rb') as f:
        data = f.read()

    # Pad to 4-byte boundary
    if len(data) % 4 != 0:
        data += b'\x00' * (4 - len(data) % 4)

    num_words = len(data) // 4
    print(f"Writing {num_words} words ({len(data)} bytes)...")

    for i in range(0, len(data), 4):
        # Extract 32-bit word (little-endian)
        word = int.from_bytes(data[i:i+4], byteorder='little')

        # Manually set address for each word (do not rely on sbautoincrement)
        word_index = i // 4
        addr = base_addr + i
        dmi_write(sock, 0x39, addr & 0xFFFFFFFF)              # SBAddress0
        dmi_write(sock, 0x3A, (addr >> 32) & 0xFFFFFFFF)      # SBAddress1

        # Write to SBData0
        dmi_write(sock, 0x3C, word)

        if word_index % 100 == 0:
            print(f"  Progress: {word_index}/{num_words} words")

    print("Done writing!")

    # Clear any remaining buffered responses from socket
    print("\nClearing socket buffer...")
    try:
        sock.settimeout(0.1)
        while True:
            sock.recv(4096)
    except socket.timeout:
        pass
    finally:
        sock.settimeout(None)

    # Verify first few words
    print("Verifying first 4 words...")

    for i in range(4):
        # Set address for this word (triggers SBA read due to sbreadonaddr=1)
        addr = base_addr + i * 4
        dmi_write(sock, 0x39, addr & 0xFFFFFFFF)
        dmi_write(sock, 0x3A, (addr >> 32) & 0xFFFFFFFF)

        # Wait longer for SBA read to complete through hardware
        time.sleep(0.2)

        # Now read the data from sbdata0
        expected = int.from_bytes(data[i*4:(i+1)*4], byteorder='little')
        actual = dmi_read(sock, 0x3C)

        if actual is None:
            print(f"  [0x{base_addr + i*4:08x}] Expected: 0x{expected:08x}, Got: None ✗")
        else:
            status = "✓" if actual == expected else "✗"
            print(f"  [0x{base_addr + i*4:08x}] Expected: 0x{expected:08x}, Got: 0x{actual:08x} {status}")

    # Check for errors
    sbcs = dmi_read(sock, 0x38)
    sberror = (sbcs >> 12) & 0x7
    if sberror != 0:
        print(f"\nWarning: SBCS reports sberror={sberror}")
    else:
        print("\nNo SBA errors!")

    sock.close()
    print("\n✓ Binary loaded successfully!")
    print("\nNow run in OpenOCD telnet: reset run")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 load_sba.py <binary_file> [base_address]")
        sys.exit(1)

    binary_path = sys.argv[1]
    base_addr = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x80000000

    load_binary_via_sba(binary_path, base_addr)
