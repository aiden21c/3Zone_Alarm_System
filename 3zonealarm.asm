; Main code without the delays. Written so that it doesn't expire.
; Author: Thira (s3823593)
; Created: 03/10/2021

;**********************************************************************
; CONSTANTS AND VARIABLE DECLARATION
; define any constants and registers here
.def armed		= R8		; state of the device (armed - 1/unarmed - 0)
.def temp		= R17
.def pinCVal	= R18		; input from pinc
.def temp2		= R19
.def temp3		= R20
.def temp4		= R21
.def triggered	= R5		; initially system must not be triggered
							; triggered = 1/ not-triggered = 0
							; r0-R15 cannot hold 255.. becareful
.def correctCounter = R6	; if this is 4, then correct code entered.
.def zoneCounter = R7
.def counter = R9			; used for the delay
.def counter2 = R10			; used for the delay
.def armed2 = R11

; 4 input pin values respectively, initially needs to be 0, 0, 0, 0
.def val1 = R1
.def val2 = R2
.def val3 = R3
.def val4 = R4

.equ SP = 0xDF			; inializing the stack pointer

; Creating the equates for PortB and PortC registers:
.equ portCDDR = 0x14
.equ portCPin = 0x13
.equ portCPort = 0x15

.equ portBDDR = 0x17
.equ portBPin = 0x16
.equ portBPort = 0x18

; Equivalents for the individual key pad colomns:
.equ ColIdle = 0xFF		; all high
.equ col1Scan = 0xEF
.equ col2Scan = 0xDF
.equ col3Scan = 0xBF
.equ col4Scan = 0x7F

;************************************************************************************
; STARTING PROGRAM HERE:
main:
	; clr password variables: 0000
	CLR val1
	CLR val2
	CLR val3
	CLR val4

	CLR armed
	CLR triggered

	LDI  TEMP,  SP
	OUT  0x3D,  TEMP

	CALL Init			; calling the initialization function.
;	CALL initTimer0

	mainloop1:
		; need to display the arm state of the alarm
		CLR temp			; 0x01 - unarmed		; 0x02 = armed
		CPSE temp, armed
		RJMP jmpdisplayarmed
		RJMP jmpdisplayunarmed

		mainloop2:
			CLR temp3
			CLR temp2
			CALL ReadKP		; returns read value in temp

			CP temp3, temp2	; if not 0, then key has been pressed
			BREQ mainloop2	; loops back if no key press
			CP armed, temp2
			BREQ sysUnarmed

			; if not sysUnarmed, then goes through sysArmed:
			sysArmed:
				CLR zoneCounter
				
				checkA:
				LDI temp2, 0x0C	; zone A
				CP temp, temp2	
				BREQ jmpZoneATriggered

				checkB:
				LDI temp2, 0x0D	; zone B
				CP temp, temp2	
				BREQ jmpZoneBTriggered

				checkC:
				LDI temp2, 0x0E	; zone C
				CP temp, temp2	
				BREQ jmpZoneCTriggered

				contZone:
				CLR temp2
				CP temp2, zoneCounter
				BRNE jmpZoneTriggered			; will check if the correct code has been entered & wait for correct code
				
				LDI temp2, 0x0B					; value of # into temp2
				CPSE temp2, temp				; temp from ReadKP = #
				RJMP armedNotHash				; insctruction skipped if equal

				armedHash:						; chaneges passcode
				LDI temp2, 0x04
				RJMP jmpCheckCode1
				armedHashcont:
				CP correctCounter, temp2
				BREQ codeCorrectArmed

				armedNotHash:
				CALL checkCode0
				LDI temp2, 0x04
				CP correctCounter, temp2
				BREQ noneTriggered
				RJMP mainloop1
				
				noneTriggered:
				; if nothing is triggered then simply display the armed/disarmed state
				CALL armSys
				RJMP mainloop2

				codeCorrectArmed:
				CALL Read4
				CALL displayarmed
				RJMP mainloop1

				; JUMP to ZONEATRIGGERED:
				jmpZoneATriggered:
					CALL zoneAtriggered
					JMP contZone

				; JUMP to ZONEBTRIGGERED:
				jmpZoneBTriggered:
					CALL zoneBtriggered
					JMP contZone

				; JUMP to ZONECTRIGGERED:
				jmpZoneCTriggered:
					CALL zoneCtriggered
					JMP contZone

				; JUMP to ZONETRIGGERED:
				jmpZoneTriggered:
					RJMP zoneTriggered
			
			sysUnarmed:
				; TODO: flash LEDS 4 times at a rate of 2 Hz
				LDI temp2, 0x00
				CP temp3, temp2		; if 0 then ReadKP not pressed
				BREQ mainloop2

				; testing:
				;LDI temp3, 0xF0
				;OUT PORTB, temp3
				;CLR temp3

				; comparing if the input value is #
				LDI temp2, 0x0B	; value of # into temp2

				CPSE temp2, temp		; temp from ReadKP = #
				RJMP notHash			; insctruction skipped if equal
				
				unarmedHash:
				LDI temp2, 0x04
				RJMP jmpCheckCode0
				unarmedHashcont:
				CP	correctCounter, temp2		; if same then code correct
				BREQ codeCorrect
				RJMP mainloop1

				; if the input is not #:
				notHash:
				CALL checkCode0
				contnotHash:
				LDI temp2, 0x04
				CP temp2, correctCounter
				BREQ jmpArmSys1

				codeCorrect:
					CALL read4
					CALL displayarmed
					RJMP mainloop1

; JUMPING TO DISPLAYUNARMED:
jmpdisplayunarmed:
	CALL displayunarmed
	RJMP mainloop2
	
; JUMPING TO DISPLAYARMED:
jmpdisplayarmed:
	CALL displayarmed
	RJMP mainloop2

; JUMP to checkCode:
jmpCheckCode0:
	CALL checkCode
	RJMP unarmedHashcont

; JUMP to checkCode0:
jmpCheckCode:
	CALL checkCode0
	RJMP armedHashcont

jmpCheckCode1:
	CALL checkCode
	RJMP armedHashcont
	

; JUMP to armSys:
jmpArmSys1:
	CALL armSys
	JMP mainloop2



; **************************************************************************************
; USER-FUNCTIONS

; TODO: edit check code to see if * is enterd, if so then exit all kind of

; ZONE TRIGGERED (NEEDS TO FLASH LEDs AS SIREN):
zoneTriggered:
	PUSH temp3
	PUSH temp2
	PUSH temp
	LDI temp, 0x01
	MOV triggered, temp	; remains at 1 until the code has been entered

	CALL leavingArea	; simulates the occupants leaving the area = 40s

	triggeredLoop:
		CALL checkCode
		LDI temp3, 0x04
		CP temp3, correctCounter
		BREQ exitTriggered
		RJMP triggeredLoop	; therefore keeps looping until the correct code is entered

	exitTriggered:
		CLR triggered	; not triggered anymore

		; the system has been disarmed now:
		CALL displayunarmed	; will set armed = 0
		; TODO: flash all LEDs x4 at 2Hz

		CALL armSys	; rearming the system
		POP temp3
		POP temp2
		POP temp
		RJMP mainloop1

; ZONE A TRIGGERED:
zoneAtriggered:
	PUSH temp
	PUSH temp2

	LDI temp4, 0x83			; 1000 0011
	LDI r22, 0x81			; 1000 0001

	CALL FlashLeds		; flashes LEDs 4 times at 2Hz

	LDI temp, 0x03			; armed
	LDI temp2, 0x80			; 1000 0000
	OR temp, temp2			; logical OR and leave in immediate
	OUT portBport, temp
	INC zoneCounter
	POP temp
	POP temp2
	RET

; ZONE B TRIGGERED:
zoneBtriggered:
	PUSH temp
	PUSH temp2

	LDI temp4, 0x43			; 0100 0011 = 0x43
	LDI r22, 0x41			; 0100 0001 = 0x41

	CALL FlashLeds		; flashes LEDs 4 times at 2Hz

	LDI temp, 0x03			; armed
	LDI temp2, 0x40			; 0100 0000
	OR temp, temp2			; logical OR and leave in immediate
	OUT portBport, temp
	INC zoneCounter
	POP temp
	POP temp2
	RET

; ZONE C TRIGGERED:
zoneCtriggered:
	PUSH temp
	PUSH temp2

	LDI temp4, 0x23			; 0010 0011 = 0x23
	LDI r22, 0x21			; 0010 0001 = 0x21

	CALL FlashLeds		; flashes LEDs 4 times at 2Hz

	LDI temp, 0x03			; armed
	LDI temp2, 0x20			; 0010 0000
	OR temp, temp2			; logical OR and leave in immediate
	OUT portBport, temp
	INC zoneCounter
	POP temp
	POP temp2
	RET

; CHECK CORRECT CODE ENTERED OR NOT:
checkCode:
	PUSH temp2
	PUSH temp4
	CLR correctCounter
	CLR temp2
	CLR temp4

	CPSE temp2, armed
	RJMP checkCodeArmed
	RJMP checkCodeUnarmed

	code1:
	CALL ReadKP
	CP temp3, temp2
	BREQ code1

	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT PORTB, temp4

	CP temp, val1
	BRNE exitCheck
	INC correctCounter

	code2:
	CALL ReadKP
	CP temp3, temp2
	BREQ code2
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	CP temp, val2
	BRNE exitCheck
	INC correctCounter

	code3:
	CALL ReadKP
	CP temp3, temp2
	BREQ code3
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	CP temp, val3
	BRNE exitCheck
	INC correctCounter

	code4:
	CALL ReadKP
	CP temp3, temp2
	BREQ code4
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	CP temp, val4
	BRNE exitCheck
	INC correctCounter

	exitCheck:
	POP temp2
	POP temp4
	RET

	checkCodeUnarmed:
	PUSH temp2
	LDI temp2, 0x01
	MOV armed2, temp2
	POP temp2
	RJMP code1

	checkCodeArmed:
	PUSH temp2
	LDI temp2, 0x02
	MOV armed2, temp2
	POP temp2
	RJMP code1



; CHECKING IF THE SYSTEM IS ARMED OR NOT, THEN SETTING CORRECT STATE:
armSys:
	PUSH temp
	LDI temp, 0x00	; unarmed check
	CP temp, armed
	BREQ callDisplayArmed
	CP temp, armed
	BRNE callDisplayUnarmed
	contArmSys:
	POP temp
	RET

callDisplayArmed:
	CALL displayarmed
	RJMP contArmSys 

callDisplayUnarmed:
	CALL displayunarmed
	RJMP contArmSys 

; DISPLAY ARMED:
displayarmed:
	PUSH temp
	CLR temp
	LDI temp, 0x02			; shows red led
	OUT portBPort, temp
	LDI temp, 0x01
	MOV armed, temp
	POP temp
	RET

; DISPLAY UNARMED
displayunarmed:
	PUSH temp
	CLR temp
	LDI temp, 0x01			; shows green led
	OUT portBPort, temp
	LDI temp, 0x00
	MOV armed, temp
	POP temp
	RET

; CHECK CORRECT CODE ENTERED OR NOT:
checkCode0:
	PUSH temp2
	PUSH temp4
	CLR correctCounter
	CLR temp2
	CLR temp4

	CPSE temp2, armed
	RJMP checkCodeArmed0
	RJMP checkCodeUnarmed0

	; temp already contains the first value
	code10:
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			; xxxx 00xx
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	CP temp, val1
	BRNE exitCheck0
	INC correctCounter

	code20:
	CALL ReadKP
	CP temp3, temp2
	BREQ code20
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT PORTB, temp4
	CP temp, val2
	BRNE exitCheck0
	INC correctCounter

	code30:
	CALL ReadKP
	CP temp3, temp2
	BREQ code30
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT PORTB, temp4
	CP temp, val3
	BRNE exitCheck0
	INC correctCounter

	code40:
	CALL ReadKP
	CP temp3, temp2
	BREQ code40
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT PORTB, temp4
	CP temp, val4
	BRNE exitCheck0
	INC correctCounter

	exitCheck0:
	POP temp2
	POP temp4
	RET

	checkCodeUnarmed0:
	PUSH temp2
	LDI temp2, 0x01
	MOV armed2, temp2
	POP temp2
	RJMP code10

	checkCodeArmed0:
	PUSH temp2
	LDI temp2, 0x02
	MOV armed2, temp2
	POP temp2
	RJMP code10

; READING 4 VALUES FROM THE USER (PASSCODE)
Read4:
	CLR temp2			; during this function, we will take input from the user for new password
	CLR temp3
	CLR temp4
	
	CPSE temp2, armed
	RJMP Read4Armed
	RJMP Read4Unarmed

	reading1:			; waits for the user to finish selecting the number
	CALL ReadKP			; returns value in temp
	CP temp3, temp2		; temp3 returning 0 means no value has been entered. therefore loops back until the value has been entered.
	BREQ reading1		; NOTE: consider timeouts after fully developing the code.
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	MOV val1, temp

	reading2:
	CALL ReadKP			; returns value in temp
	CP temp3, temp2
	BREQ reading2
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	MOV val2, temp

	reading3:
	CALL ReadKP			; returns value in temp
	CP temp3, temp2
	BREQ reading3
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	MOV val3, temp

	reading4:
	CALL ReadKP			; returns value in temp
	CP temp3, temp2
	BREQ reading4
	MOV temp4, temp
	LSL temp4			; left shifting by 4
	LSL temp4			
	LSL temp4			
	LSL temp4	
	OR temp4, armed2
	OUT portBPort, temp4
	MOV val4, temp

	RET					; return to main function

	Read4Unarmed:
	PUSH temp2
	LDI temp2, 0x01
	MOV armed2, temp2
	POP temp2
	RJMP reading1

	Read4Armed:
	PUSH temp2
	LDI temp2, 0x02
	MOV armed2, temp2
	POP temp2
	RJMP reading1

; FUNCTIONS TO HELP KEEP TRACK
addfunction:
	PUSH temp
	LDI temp, 0x01
	ADD temp2, temp
	POP temp
	RET

addfunction2:
	PUSH temp
	LDI temp, 0x01
	ADD temp3, temp
	POP temp
	RET


; READING KEYPAD:
ReadKP:
	;LDI	Temp, 0x03           ;dummy value for testing purposes only
	PUSH temp2    
	CLR temp2
	CLR temp3

	; Scanning Col1:
	LDI temp2, col1Scan
	OUT portCPort, temp2
	CALL Delay	; delay to allow synchronization
	IN pinCVal, portCPin	; reading input on pinC
	CP pinCVal, temp2	; comparing, if the two values are the same no key has been pressed
	BRNE col1Found	; only branches if a key has been pressed

	; Scanning Col2:
	LDI temp2, col2Scan
	OUT portCPort, temp2
	CALL Delay
	IN pinCVal, portCPin
	CP pinCVal, temp2
	BRNE col2Found

	; Scanning Col3:
	LDI temp2, col3Scan
	OUT portCPort, temp2
	CALL Delay
	IN pinCVal, portCPin
	CP pinCVal, temp2
	BRNE col3Found

	; Scanning Col4:
	LDI temp2, col4Scan
	OUT portCPort, temp2
	CALL Delay
	IN pinCVal, portCPin
	CP pinCVal, temp2
	BRNE col4Found
		
	exitScan:
	POP temp2
	RET

		col1Found:
			CALL Debounce
			CALL convertValue
			CALL addfunction2
			RJMP exitScan

		col2Found:
			CALL Debounce
			CALL convertValue
			CALL addfunction2
			RJMP exitScan

		col3Found:
			CALL Debounce
			CALL convertValue
			CALL addfunction2
			RJMP exitScan

		col4Found:
			CALL Debounce
			CALL convertValue
			CALL addfunction2
			RJMP exitScan

Debounce:
	IN temp2, portCPin
	CP temp2, pinCVal
	BREQ Debounce
	RET

convertValue:						; reading the value of the pins from the KeyTable
	LDI ZH, high(keyTable << 1)
	LDI ZL, low(keyTable << 1)

	CLR temp3
	ADD ZL, pinCVal
	ADC ZH, temp3
	LPM temp, Z

	RET

Delay:
         PUSH R16			; save R16 and 17 as we're going to use them
         PUSH R17       ; as loop counters
         PUSH R0        ; we'll also use R0 as a zero value
         CLR R0
         CLR R16        ; init inner counter
         CLR R17        ; and outer counter
L1:      DEC R16         ; counts down from 0 to FF to 0
			CPSE R16, R0    ; equal to zero?
			RJMP L1			 ; if not, do it again
			CLR R16			 ; reinit inner counter
L2:      DEC R17
         CPSE R17, R0    ; is it zero yet?
         RJMP L1			 ; back to inner counter
;
         POP R0          ; done, clean up and return
         POP R17
         POP R16
         RET

; Delay for 2Hz, therefore, 0.5s :
Delay2Hz:
	push r22
	push r23
	push r24
	ldi  r22, 31
    ldi  r23, 113
    ldi  r24, 30
	L3: dec  r24
		brne L3
		dec  r23
		brne L3
		dec  r22
		brne L3
		nop
	pop r22
	pop r23
	pop r24
	RET

; 2Hz flashing:
FlashLeds:
	PUSH temp
	
	; using temp4 and r22
	; temp4 - 1
	; r22	- 2

	MOV temp, r22
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, temp4		
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, r22
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, temp4		
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, r22
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, temp4		
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, r22
	OUT portBPort, temp
	CALL Delay2Hz

	MOV temp, temp4		
	OUT portBPort, temp
	CALL Delay2Hz

	POP temp
	RET						; return


leavingArea:				; delay to simulate the occupants leaving the area = 40s
	push r22
	push r23
	push r24
	push r25
		ldi  r22, 10
		ldi  r23, 132
		ldi  r24, 11
		ldi  r25, 66
		L4: dec  r25
			brne L4
			dec  r24
			brne L4
			dec  r23
			brne L4
			dec  r22
			brne L4
			rjmp PC+1
	pop r22
	pop r23
	pop r24
	pop r25
	ret



; INITIALIZATION OF INPUT AND OUTPUT PORTS:
init:	; initializing function
	PUSH temp

	CLR pinCVal
	CLR armed

	LDI temp, 0xF0
	OUT portCDDR, temp

	; Enabling the pull up resistors on the row inputs:
	LDI temp, 0x0F
	OUT portCPort, temp

	; setting all colomns to high ensuring the pull up resistors are enabled:
	LDI temp, colIdle
	OUT portCPort, temp

	; setting portB (all LEDs as outputs and should be 0 initially)
	LDI temp, 0xFF
	OUT portBDDR, temp
	CLR temp
	LDI temp, 0x00
	OUT portBPort, temp

	POP temp
  	RET

	

keyTable:
		;	 0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;0
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;1
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;2
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;3
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;4
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;5
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;6
		.db 255, 255, 255, 255, 255, 255, 255,  15, 255, 255, 255,  14, 255,  13,  12, 255	;7
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;8
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;9
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;A
		.db 255, 255, 255, 255, 255, 255, 255,  11, 255, 255, 255,   9, 255,   6,   3, 255	;B
		.db 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255	;C
		.db 255, 255, 255, 255, 255, 255, 255,   0, 255, 255, 255,   8, 255,   5,   2, 255	;D
		.db 255, 255, 255, 255, 255, 255, 255,  10, 255, 255, 255,   7, 255,   4,   1, 255	;E