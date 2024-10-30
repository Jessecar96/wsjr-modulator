This is the working design of the Weather STAR Jr Subcarrier modulator PCB and example code. 

This is not a rounded solution that includes data, instead this is the hardware part necessary to communicate with the weatherstar itself. 

There is an example file that encodes a simple frame and sends it over and over to the unit. You will be required to write your own solution for sending teletext frames. 

the example code is written in BASCOM-AVR, and targets the Arduino Mega. the PCB plugs into the Arduino Mega with a ribbon cable. 

the FSK Modulator is a simple AD9835 chinese breakout PCB with all of the supporting components on-board. 

License: https://creativecommons.org/licenses/by-nc-sa/4.0/
