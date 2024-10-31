' *
' * Title         : FSK example.bas
' * Version       : 1.0
' * Target MCU    : ATmega2560
' * Author        : techknight
' * Program code  : BASCOM AVR
' * Hardware req. : Arduino Mega, WeatherSTAR Jr/III
' * Description   : Clocks 37-byte control Packets to the WeatherSTAR Jr
' ***************************************************************************

$regfile = "m2560def.dat"                                   'use ATmega2560 (Mega256 Base System)
$crystal = 16000000                                         '16 Mhz

$hwstack = 128                                              ' default use 32 for the hardware stack
$swstack = 32                                               'default use 10 for the SW stack
$framesize = 64                                             'default use 40 for the frame space

'Define hardware uart on Arduino.
Config Com1 = 115200 , Synchrone = 0 , Parity = None , Stopbits = 1 , Databits = 8 , Clockpol = 0
Config Serialin = Buffered , Size = 254                     ' We are using the hardware UART, in buffered interrupt mode.


'**************************************************************************************************************************
'BEGIN DRIVER DECLARATION
'**************************************************************************************************************************
'Define pins used by the WeatherSTAR Jr. (serial mode)
Readenable Alias Portl.4                                    'RTS in Schematic   (Request to Send signal, Trigger, to transmit the FIFO contents to the receiver)
Writeenable Alias Portl.0                                   '/W In Schematic    (Write strobe to insert 16-bits of data into the FIFO)
Empty Alias Pinl.1                                          '/EF in Schematic   (Signal to indicate the FIFO is empty and ready for a new frame)
Periphreset Alias Portl.2                                   '/RST in Schematic (Resets both the FIFO, and DDS chip into initial states)
Direction Alias Portl.3                                     'FLDIR in Schematic (FIFO when in reset mode reads this for cascading, or MSB/LSB indication for data direction)
Ddsenable Alias Portl.5                                     'DDSCS in Schematic (FSync on DDS chip, used to select the chip when the SPI is communicating with it)

Fifolow Alias Porta                                         'Low 8-bits for FIFO Data
Fifohigh Alias Portc                                        'High 8-bits for FIFO Data

Config Portl.1 = Input
Config Fifolow = Output
Config Fifohigh = Output
Config Readenable = Output
Config Writeenable = Output
Config Empty = Input
Config Periphreset = Output
Config Direction = Output
Config Ddsenable = Output
Config Portb.0 = Output                                     'Compensate for the SS line (not used, but has to be driven high or the AVR will get stuck in slave-only mode, Painful experience)

'Setup the port pins for the initial state.
Reset Readenable                                            'reading not allowed
Reset Writeenable                                           'write not allowed
Set Periphreset                                             'Hold the DDS, and the FIFO into RESET mode until we are ready.
Reset Direction                                             'Sets our chip in to single mode.
Set Ddsenable                                               'Make sure we do not have our IC selected
Fifolow = 0
Fifohigh = 0

'Setup the SPI for the AD9834 DDS Baud Clock Generator.
Set Portb.0                                                 'Set SS High (Not used, must be high to stay in master mode)
Config Spi = Hard , Interrupt = Off , Data_order = Msb , Master = Yes , Polarity = High , Phase = 0 , Clockrate = 4 , Noss = 1
Spiinit                                                     'Initialize the SPI hardware
Set Ddsenable                                               'Make sure our DDS select state is maintained

'Declare Variables used in the driver process
Dim Dataframe(38) As Byte                                   'Array used to build and send the 37 byte Teletext Data.
Dim Dataframe2(38) As Byte                                  'Array used to build and send the 37 byte Teletext Data.
Dim Dataframe3(38) As Byte                                  'Array used to build and send the 37 byte Teletext Data.
Dim Ddsword(2) As Byte                                      '16 bit array for DDS values.
Dim I As Byte                                               'Index counter to keep track of loops.
Dim Iv As Long                                              'Contains the 21-bits of data for the XOR encipher routine
Dim Shiftivcount As Byte                                    'Contains the count value of each logical shift of the IV Register


'Declare Subroutines for the required operation.
Declare Function Gethammingcode(byval Databyte As Byte) As Byte
Declare Function Calculateparity(byval Character As Byte) As Byte
Declare Function Encryptbyte(byval Databyte As Byte) As Byte
Declare Sub Initperipherals()
Declare Sub Setfrequency(byval Frequency As Long)


'**************************************************************************************************************************
'END DRIVER DECLARATION
'**************************************************************************************************************************

Disable Interrupts

'Build Test Page 51 header (Weather Warning) .
Dataframe(1) = &H55                                         'Clock Run In
Dataframe(2) = &H55                                         'Clock Run In
Dataframe(3) = &H27                                         'Teletext Framing Code (Activates the decoders)
Dataframe(4) = &H80                                         'Row 0
Dataframe(5) = Gethammingcode(&B0000)                       'OMCW Bit 4 (Weather Warning)
Dataframe(6) = Gethammingcode(&B0101)                       'OMCW Bit 6, 8 (Region Seperator, Solid Background in LDL)
Dataframe(7) = Gethammingcode(&B0000)                       'OMCW 0
Dataframe(8) = Gethammingcode(&B0001)                       'OMCW Bit15,16 Warning Crawl on Page 51.
Dataframe(9) = &HE3                                         'Page Number High 16
Dataframe(10) = Gethammingcode(&H02)                        'Page Number Low 16 (Page 51)
Dataframe(11) = &H52                                        'ADDR 1 4h                      (Mine is 0041A09A. First byte is market bits.)
Dataframe(12) = &H80                                        'ADDR 2 1h
Dataframe(13) = &H80                                        'ADDR 3 Ah
Dataframe(14) = &H80                                        'ADDR 4 0h
Dataframe(15) = &H49                                        'ADDR 5 9h
Dataframe(16) = &H2A                                        'ADDR 6 Ah
Dataframe(17) = &H31                                        'Line Count: Simple 1 line of text
Dataframe(18) = &H80                                        'Page Attributes: Weather Warning
Dataframe(19) = &H80                                        'Page Attributes
Dataframe(20) = Gethammingcode(&B0001)                      'Line 1 Attributes (Add separator bar)
Dataframe(21) = Gethammingcode(&B0000)                      'Line 1 Attributes
Dataframe(22) = &H80                                        'Line 2 Attributes
Dataframe(23) = &H80                                        'Line 2 Attributes
Dataframe(24) = &H80                                        'Line 3 attributes
Dataframe(25) = &H80                                        'Line 3 Attributes
Dataframe(26) = &H80                                        'Line 4 Attributes
Dataframe(27) = &H80                                        'Line 4 Attributes
Dataframe(28) = &H80                                        'Line 5 Attributes
Dataframe(29) = &H80                                        'Line 5 Attributes
Dataframe(30) = &H80                                        'Line 6 Attributes
Dataframe(31) = &H80                                        'Line 6 Attributes
Dataframe(32) = &H80                                        'Line 7 Attributes
Dataframe(33) = &H80                                        'Line 7 Attributes
Dataframe(34) = &H80                                        'OMCW Extension (Unused here)
Dataframe(35) = &H80                                        'OMCW Extension (Unused here)
Dataframe(36) = &H80                                        'Line 8/9 Attributes
Dataframe(37) = &H80                                        'Line 8/9 Attributes
Dataframe(38) = 0

'Build Test Page 51 Row 1 (Weather Warning).
Dataframe2(1) = &H55                                        'Clock Run In
Dataframe2(2) = &H55                                        'Clock Run In
Dataframe2(3) = &H27                                        'Teletext Framing Code (Activates the decoders)
Dataframe2(4) = &H31                                        'Row 1
Dataframe2(5) = Gethammingcode(&B0000)                      'Text Width/Height.
Dataframe2(6) = Calculateparity( "A")                       'Char 1
Dataframe2(7) = Calculateparity( "B")                       'Char 2
Dataframe2(8) = Calculateparity( "C")                       'Char 3
Dataframe2(9) = Calculateparity( "D")                       'Char 4
Dataframe2(10) = Calculateparity( "E")                      'Char 5
Dataframe2(11) = Calculateparity( "F")                      'Char 6
Dataframe2(12) = Calculateparity( "G")                      'Char 7
Dataframe2(13) = Calculateparity( "H")                      'Char 8
Dataframe2(14) = Calculateparity( "I")                      'Char 9
Dataframe2(15) = Calculateparity( "J")                      'Char 10
Dataframe2(16) = Calculateparity( "K")                      'Char 11
Dataframe2(17) = Calculateparity( "L")                      'Char 12
Dataframe2(18) = Calculateparity( "M")                      'Char 13
Dataframe2(19) = Calculateparity( "N")                      'Char 14
Dataframe2(20) = Calculateparity( "O")                      'Char 15
Dataframe2(21) = Calculateparity( "P")                      'Char 16
Dataframe2(22) = Calculateparity( "Q")                      'Char 17
Dataframe2(23) = Calculateparity( "R")                      'Char 18
Dataframe2(24) = Calculateparity( "S")                      'Char 19
Dataframe2(25) = Calculateparity( "T")                      'Char 20
Dataframe2(26) = Calculateparity( "U")                      'Char 21
Dataframe2(27) = Calculateparity( "V")                      'Char 22
Dataframe2(28) = Calculateparity( "W")                      'Char 23
Dataframe2(29) = Calculateparity( "X")                      'Char 24
Dataframe2(30) = Calculateparity( "Y")                      'Char 25
Dataframe2(31) = Calculateparity( "Z")                      'Char 26
Dataframe2(32) = Calculateparity( "0")                      'Char 27
Dataframe2(33) = Calculateparity( "1")                      'Char 28
Dataframe2(34) = Calculateparity( "2")                      'Char 29
Dataframe2(35) = Calculateparity( "3")                      'Char 30
Dataframe2(36) = Calculateparity( "4")                      'Char 31
Dataframe2(37) = Calculateparity( "5")                      'Char 32
Dataframe2(38) = 0

'Example TOD Packet.(idle here)
Dataframe3(1) = &H55                                        'Clock Run In
Dataframe3(2) = &H55                                        'Clock Run In
Dataframe3(3) = &H27                                        'Teletext Framing Code (Activates the decoders)
Dataframe3(4) = &H80                                        'row 0
Dataframe3(5) = Gethammingcode(&B0000)                      'OMCW Bit 4 (Weather Warning)
Dataframe3(6) = Gethammingcode(&B0101)                      'OMCW Bit 6, 8 (Region Seperator, Solid Background in LDL)
Dataframe3(7) = Gethammingcode(&B0000)                      'OMCW 0
Dataframe3(8) = Gethammingcode(&B0001)                      'OMCW Bit15,16 Warning Crawl on Page 51.
Dataframe3(9) = &H80                                        'Page Number High 16
Dataframe3(10) = &H80                                       'Page Number Low 16 (Page 0)
Dataframe3(11) = Gethammingcode(&B0010)                     'Timezone
Dataframe3(12) = Gethammingcode(3)                          'Day
Dataframe3(13) = Gethammingcode(1)                          'Month
Dataframe3(14) = Gethammingcode(1)                          'Day Of Month High
Dataframe3(15) = Gethammingcode(6)                          'Day Of Month Low
Dataframe3(16) = Gethammingcode(8)                          'Hours
Dataframe3(17) = Gethammingcode(3)                          'Minutes High
Dataframe3(18) = Gethammingcode(2)                          'Minutes Low
Dataframe3(19) = Gethammingcode(0)                          'Seconds High
Dataframe3(20) = Gethammingcode(0)                          'Seconds Low
Dataframe3(21) = Gethammingcode(1)                          'AM/PM
Dataframe3(22) = Gethammingcode(0)
Dataframe3(23) = Gethammingcode(0)
Dataframe3(24) = Gethammingcode(0)
Dataframe3(25) = Gethammingcode(0)
Dataframe3(26) = Gethammingcode(0)
Dataframe3(27) = Gethammingcode(0)
Dataframe3(28) = Gethammingcode(0)
Dataframe3(29) = Gethammingcode(0)
Dataframe3(30) = Gethammingcode(0)
Dataframe3(31) = Gethammingcode(0)
Dataframe3(32) = Gethammingcode(1)                          'Checksum High
Dataframe3(33) = Gethammingcode(&Hb)                        'Checksum Low
Dataframe3(34) = &H80                                       'OMCW Extension
Dataframe3(35) = &H80                                       'OMCW Extension
Dataframe3(36) = &H80                                       'Unused
Dataframe3(37) = &H80                                       'Unused


Initperipherals                                             'Initialize our FIFO and DDS IC, Set DDS to Initial Frequency.

'Test loop to send 2 packets out on rotation.
Do
   'Reset IV
   Iv = 0

   Fifolow = 0
   Fifohigh = 0
   Reset Writeenable                                        'Write Zeros into the FIFO for the "wrap-around" bug, and to reset IV to 0.
   Set Writeenable

   'Send out test packet one
   I = 1
   Do
      Fifolow = Encryptbyte(dataframe(i))                   'Set PortA to first 8 bits of FIFO Input (Two bytes of the packet sent at a time)
      Incr I                                                'Increment write pointer
      Fifohigh = Encryptbyte(dataframe(i))                  'Set PortC to Last 8 bits of FIFO Input  (Two bytes of the packet sent at a time)
      Incr I                                                'Increment write pointer
      !nop                                                  'Delay one CPU Cycle (Give time for data lines to settle before triggering the FIFO Write)
      Reset Writeenable                                     'Strobe the FIFO to write in the loaded 16-bit value.
      Set Writeenable                                       'De-Assert the write strobe signal.
   Loop Until I >= 38                                       'I am actually sending 38 bytes. not 37 here. the 38th byte is a 00. (Adhering to 16-bit alignment not 8)

   Fifolow = 0                                              'Pad loaded frame with 2 Bytes of 00s. (Assures a stable line state for IV Initialization in the receiver)
   Fifohigh = 0
   Reset Writeenable                                        'Write Zeros into the FIFO for the "wrap-around" bug, and to reset IV to 0.
   Set Writeenable

   Set Readenable                                           'Pull the trigger to enable the VBI signal for FIFO dumping. (Think of RS232 Flow Control here)
   Reset Readenable                                         'Reset the trigger. (Once its pulled, dont leave it set or you now have an automatic rifle)
   Do
   Loop Until Empty = 0                                     'Wait until FIFO Empty (End of Transmission)

   Iv = 0

   Fifolow = 0
   Fifohigh = 0
   Reset Writeenable                                        'Write Zeros into the FIFO for the "wrap-around" bug, and to reset IV to 0.
   Set Writeenable

   'Send out test packet two
   I = 1
   Do
      Fifolow = Encryptbyte(dataframe2(i))
      Incr I
      Fifohigh = Encryptbyte(dataframe2(i))
      Incr I
      !nop
      Reset Writeenable
      Set Writeenable
   Loop Until I >= 38

   Fifolow = 0
   Fifohigh = 0
   Reset Writeenable                                        'Write Zeros into the FIFO for the "wrap-around" bug, and to reset IV to 0.
   Set Writeenable

   Set Readenable                                           'Pull the trigger to enable the VBI signal for FIFO dumping.
   Reset Readenable
   Do
   Loop Until Empty = 0                                     'Wait until FIFO Empty (End of Transmission)

Loop

'**************************************************************************************************************************
'System Operation Functions                                                                                               *
'**************************************************************************************************************************
Function Gethammingcode(databyte As Byte) As Byte
   Select Case Databyte
      Case 0
         Gethammingcode = &H80
      Case 1
         Gethammingcode = &H31
      Case 2
         Gethammingcode = &H52
      Case 3
         Gethammingcode = &HE3
      Case 4
         Gethammingcode = &H64
      Case 5
         Gethammingcode = &HD5
      Case 6
         Gethammingcode = &HB6
      Case 7
         Gethammingcode = &H7
      Case 8
         Gethammingcode = &HF8
      Case 9
         Gethammingcode = &H49
      Case 10
         Gethammingcode = &H2A
      Case 11
         Gethammingcode = &H9B
      Case 12
         Gethammingcode = &H1C
      Case 13
         Gethammingcode = &HAD
      Case 14
         Gethammingcode = &HCE
      Case 15
         Gethammingcode = &H7F
      Case Else
         Gethammingcode = 0
   End Select
End Function

'This calculates Odd-Parity for ASCII Codes. Parity bit is the 8th Bit.
'Sadly, this implementation cuts your ASCII table from 255 bytes to 127 bytes.
Function Calculateparity(byval Character As Byte) As Byte
   Dim Shiftchar As Byte
   Dim Count As Byte
   Dim Carry As Byte

   I = 0
   Count = 0

   Shiftchar = Character

   For I = 0 To 7 Step 1
      Shift Shiftchar , Right                               'Shift out the current LSB into the Carry.
      Carry = Sreg And 1                                    'Check carry flag if the last bit was a 1
      Count = Count + Carry                                 'Add that one to our count if it was a 1, otherwise 0
   Next

   Carry = Count Mod 2                                      'Math inside an If condition can be sketchy, so lets do it here instead
   Shiftchar = Character
   If Carry = 1 Then                                        'Odd number of bits detected
      Reset Shiftchar.7                                     'Ensure 8th bit is clear
      Calculateparity = Shiftchar                           'Odd parity is 0, so we just simply return what we sent
   Else                                                     'We have an even number of bits
      Set Shiftchar.7
      Calculateparity = Shiftchar
   End If                                                   '
End Function

'This function performs a bit-level XOR encryption using a 21-bit IV Work register.
Function Encryptbyte(byval Databyte As Byte) As Byte
   Dim Shiftbyte As Byte
   Dim Endbyte As Byte
   Dim Count2 As Byte
   Dim Bita , Bitb , Bitc , Countset As Bit
   Dim Carryflag As Byte
   Dim Ihatelinebylinebasic As Byte

   Shiftbyte = Databyte                                     'Store our plaintext byte to be enciphered
   Count2 = 0

   For Count2 = 0 To 7 Step 1                               'Loop through 8 bits
      Shift Shiftbyte , Right                               'Shift our LSB into the Carry flag
      Carryflag = Sreg And 1                                'Store ONLY the Carry flag

      Bita = Iv.2 Xor Iv.19                                 'XOR IV Work Register Bits 2, and 19
      Countset = Iv.0 Xor Iv.8                              'XOR IV Work Register Bits 0, and 8.

      If Countset = 1 Then                                  'if Previous XOR operation resulted in a high, Reset the counter
         Shiftivcount = 0
      End If

      Ihatelinebylinebasic = Shiftivcount And 31            'Store only the first 5 bits of our count register
      If Ihatelinebylinebasic = 31 Then                     'if all 5 bits are a 1, Our counter has tripped, so we need to set the flag as a 0
         Bitb = Bita Xor 0
      Else
         Bitb = Bita Xor 1
      End If

      Bitc = Carryflag.0 Xor Bitb                           'XOR our Key bit with our Carry (data) Bit.

      Shift Endbyte , Right                                 'Shift our ciphertext by 1
      Shift Iv , Left                                       'Shift our IV Work register by 1
      Incr Shiftivcount                                     'Increment our counter by 1

      Endbyte.7 = Bitc                                      'Store our result into the LSB of our ciphertext byte
      Iv.0 = Bitc                                           'Store our result into the LSB of our IV work register
   Next

   Encryptbyte = Endbyte
End Function

'This function RESETs the DDS chip, and FIFO, as well as sets the DDS chip to an initial value.
Sub Initperipherals()

'26771963   7.48Mhz Mark Frequency.
'26590036   7.43Mhz Mark Frequency.
'26235092   7.33Mhz Space Frequency.
'26056135   7.28Mhz Space Frequency.

Set Direction                                               'Ensure FIFO is setup as single only.

Ddsword(1) = &H22                                           'Set initial RESET state of DDS IC
Ddsword(2) = 0

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the control word
!Nop
Reset Periphreset                                           'Make sure we are in RESET.

Ddsword(1) = &B01010101                                     'Set Space Frequency Lower 14 Bits.
Ddsword(2) = &B11000111

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the upper frequency word (upper 14 bits)

Ddsword(1) = &B01000110                                     'Set Space Frequency Upper 14 Bits.
Ddsword(2) = &B00110110

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the lower frequency word (lower 14 bits)

Ddsword(1) = &B10000001                                     'Set Mark Frequency Lower 14 Bits.
Ddsword(2) = &B11111011

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the upper frequency word (upper 14 bits)

Ddsword(1) = &B10000110                                     'Set Mark Frequency Upper 14 Bits.
Ddsword(2) = &B01100010


Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the lower frequency word (lower 14 bits)
!NOP
Set Periphreset                                             'Bring our chips out of reset.
Waitus 50
Reset Direction                                             'Make sure our FIFO clocks out in the correct direction!

End Sub

'This function sets a new frequency into the DDS chip, as well as resets everything in the process.
Sub Setfrequency(byval Frequency As Long)
Dim Shiftfrequency As Long
Dim Carry2 As Byte
Dim Lowword As Word
Dim Highword As Word

Shiftfrequency = Frequency
Lowword = Shiftfrequency                                    'Grab the lower 16 bits
Lowword = Lowword And &B0011111111111111                    'Grab only the lower 14 bits
Lowword = Lowword Or &B0100000000000000                     'Make sure buts 15/16 have correct DDS address

Shift Shiftfrequency , Left , 2                             'move up the frequency by 2 bits to grab the upper 14 bits.
Highword = Highw(shiftfrequency)                            'Grab the upper 16 bits
Highword = Highword And &B0011111111111111                  'Grab only the upper 14 bits
Highword = Highword Or &B0100000000000000                   'Make sure bits 15/16 have correct DDS address

Ddsword(1) = High(lowword)                                  'Frequency Lower 14 Bits.
Ddsword(2) = Low(lowword)

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the upper frequency word (upper 14 bits)

Ddsword(1) = High(highword)                                 'Frequency Upper 14 Bits.
Ddsword(2) = Low(highword)

Reset Ddsenable                                             'Tell the chip we are sending data.
Spiout Ddsword(1) , 2                                       'Send out control word
Set Ddsenable                                               'We are finished sending the lower frequency word (lower 14 bits)

End Sub
