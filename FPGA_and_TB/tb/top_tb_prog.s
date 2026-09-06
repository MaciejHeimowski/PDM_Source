li hpt, 0xff
li lpt, 0x00

li r5,  0x99

li r6, %hi(page2)
li r7, %lo(page2)
b true, r6, r7

org 512

page2:

st r5,  0x00
ld r4,  0x00
ext 0

