# ==============================================================================
# Memblaze Kintex-7 Extension Connectors J1 & J4 Reference Pinout
# Extracted from MEMBLAZE扩展引脚定义.xls
#
# CRITICAL SAFETY NOTICE:
#   J1 connector power pins include 1.8V and 2.5V rails.
#   J4 connector power pins include 1.8V and 3.3V rails.
#   Before uncommenting any pin below for an external DAC/ADC/UART module,
#   verify the exact Bank VCCO voltage in Vivado Package Pins / I/O Ports view
#   and set IOSTANDARD (LVCMOS18 / LVCMOS25 / LVCMOS33 / LVDS_25) accordingly!
# ==============================================================================

# ------------------------------------------------------------------------------
# J1 (Top-Left 2x60 Connector) - FPGA User I/O Pins
# Upper row power pins: 0.9V (pin 52-53), 2.5V (pin 54-60)
# Lower row power pins: 1.8V (pin 53-57)
# ------------------------------------------------------------------------------
# J1 Upper:
# Pin  3: G22   Pin  4: H22   Pin  6: F21   Pin  7: E21   Pin  9: L17   Pin 10: F22
# Pin 12: L18   Pin 13: K19   Pin 15: F20   Pin 16: E20   Pin 18: K20   Pin 19: H19
# Pin 21: H21   Pin 22: C21   Pin 24: D21   Pin 26: G18   Pin 27: A30   Pin 28: D22
# Pin 29: B30   Pin 31: C30   Pin 32: W26   Pin 33: C22   Pin 34: G20   Pin 35: D23
# Pin 37: E23   Pin 38: D29   Pin 39: F23   Pin 40: E30   Pin 42: E29   Pin 43: A25
# Pin 44: H25   Pin 45: E24   Pin 47: E25   Pin 48: H24   Pin 49: A26   Pin 50: F25
#
# J1 Lower:
# Pin  2: F30   Pin  3: G30   Pin  5: D28   Pin  6: E28   Pin  8: F27   Pin  9: G28
# Pin 11: D26   Pin 12: C26   Pin 14: H26   Pin 15: H27   Pin 17: G24   Pin 18: G25
# Pin 20: G27   Pin 21: F26   Pin 23: E26   Pin 25: G19   Pin 26: J19   Pin 27: B20
# Pin 28: C20   Pin 30: G23   Pin 31: D24   Pin 33: C24   Pin 34: B24   Pin 36: G29
# Pin 37: F28   Pin 39: A28   Pin 40: B28   Pin 42: B25   Pin 43: C25   Pin 45: H30
# Pin 46: B27   Pin 48: C29   Pin 49: B29   Pin 51: A27   Pin 58: H20   Pin 59: A23
# Pin 60: B23

# ------------------------------------------------------------------------------
# J4 (Bottom-Right 2x60 Connector) - FPGA User I/O Pins
# Upper row power pins: 1.8V (pin 4-8)
# Lower row power pins: VCC_3.3 (pin 1-7)
# ------------------------------------------------------------------------------
# J4 Upper:
# Pin  1: W28   Pin  2: W29   Pin  3: Y28   Pin 10: AK20  Pin 12: AK25  Pin 13: AJ24
# Pin 15: AJ23  Pin 16: AJ22  Pin 18: AF22  Pin 19: AG23  Pin 21: AH22  Pin 22: AG22
# Pin 24: AH21  Pin 25: AJ21  Pin 27: AH20  Pin 28: AE20  Pin 30: AG20  Pin 31: AK21
# Pin 33: Y25   Pin 34: W27   Pin 35: AA26  Pin 36: Y26   Pin 38: AC25  Pin 40: AC24
# Pin 41: AB24  Pin 43: AA23  Pin 44: AD24  Pin 46: AD22  Pin 47: AC22  Pin 49: AE24
# Pin 50: AD23  Pin 52: AC21  Pin 53: AC20  Pin 55: AE23  Pin 56: AF23  Pin 58: AA20
# Pin 59: AB20
#
# J4 Lower:
# Pin 11: Y23   Pin 12: Y24   Pin 13: Y21   Pin 14: Y20   Pin 17: AK23  Pin 18: AK24
# Pin 19: AH25  Pin 21: AG25  Pin 22: AF21  Pin 23: AF20  Pin 24: AF25  Pin 26: AE25
# Pin 27: AB29  Pin 28: AA28  Pin 29: W26   Pin 33: AC26  Pin 35: AD26  Pin 37: AK26
# Pin 39: AJ26  Pin 40: AJ27  Pin 42: AH26  Pin 43: AH27  Pin 45: AK30  Pin 46: AK29
# Pin 48: AK28  Pin 49: AF26  Pin 51: AE26  Pin 52: AG28  Pin 54: AF28  Pin 55: AE28
# Pin 57: AG27  Pin 58: AF27
