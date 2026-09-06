# Set 2 pins as outputs, 2 as inputs
li hpt, 0xff          # 0x0000
li lpt, 0x00          # 0x0002
li r4, 0b00001100     # 0x0004
st r4, 0              # 0x0006

loop:

# Read the inputs
ld r4, 2              # 0x0008
# Shift by 2 to the left (to the outputs)
lsh r5, r4, -2        # 0x000a
# Update output pins
st r5, 1              # 0x000c
# Loop back
br true, %rel(loop)   # 0x000e
