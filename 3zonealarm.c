/*
 * 3ZoneAlarmSystem_C.c
 *
 * Created: 23/09/2021 9:59:52 PM
 * Author : Aiden
 */ 

/************************************************************************/
/*
Timer 0 math:
		At a divide by 1024, 1 count occurs every 85.3us
		This means it takes 0.02 seconds to count from 0-255
		This means we must count from 0-255 230 times to achieve a 5 second timeout count
                                                                     */
/************************************************************************/

// Armed flag		= 0x01
// Disarmed flag	= 0x02

#include <avr/io.h>
#include <avr/interrupt.h>

// Define number of keypad rows and columns, and code digits
#define rows	4
#define cols	4
#define digits	4

// Define some keypad hex values
#define	A		10
#define B		11
#define C		12
#define hash	35
#define asterix 42

// Define armed/disarmed
#define armed		1
#define disarmed	2

// Function definitions
void initialize();
void configTimer();
uint8_t readKP();
void clearLEDs();
void flashLeds();
void displayOr(uint8_t value);
uint8_t waitDebounce(uint8_t value);
uint8_t correctCodeEntered1(uint8_t currentCode[], uint8_t valueCheck[]);
uint8_t correctCodeEntered2(uint8_t currentCode[]);
uint8_t correctCodeEntered3(uint8_t currentCode[], uint8_t firstDigit);
void setNewCode(uint8_t currentCode[]);
void display(uint8_t value);
void delay();
void delayHalf();
uint8_t armSystem();

// Keypad column masks
#define IDLE					0xFF
const uint8_t colMasks[cols]	= {0xEF, 0xDF, 0xBF, 0x7F};

// Pointers to the I/O Registers
volatile uint8_t * ddrcio;
volatile uint8_t * pincio;
volatile uint8_t * portcio;

volatile uint8_t * ddrbio;
volatile uint8_t * portbio;
volatile uint8_t * pinbio;

uint8_t timeout 	= 0;

// Initialize a lookup table
const uint8_t lookup[cols][rows] =
{
	{0xEE, 0xED, 0xEB, 0xE7},
	{0xDE, 0xDD, 0xDB, 0xD7},
	{0xBE, 0xBD, 0xBB, 0xB7},
	{0x7E, 0x7D, 0x7B, 0x77}
};

const uint8_t keypad[cols][rows] =
{
	{ 1,  4,  7, asterix},
	{ 2,  5,  8,  0},
	{ 3,  6,  9, hash},
	{A, B, C, 13}
};


int main(void)
{
	cli();		// Disable all interrupt sources
	
	uint8_t keyValue	= IDLE;		// Initialized the variable used to obtain the initial key input
	uint8_t triggered	= 1;		//  Ensure the system is not triggered initially
	
	initialize();		// Initialise the I/O registers
	configTimer();		// Configure the timer for use with the "checkCode" interrupt
	
	uint8_t sysArmed	= disarmed;		// Initialise the system as disarmed
	display(sysArmed);
	
	// Initialize the code as 0000 on boot
	uint8_t currentCode[digits]	= {0x00, 0x00, 0x00, 0x00};
    
	// Continue looping forever checking key inputs
	while (1) 
    {
		// Read the Hex value of the keypad and return it as the relevant keypad value
		keyValue = readKP();
		// If the keypad has been pressed, analyse this value
		if(keyValue != IDLE) {
			
			// If the system is already armed
			if (sysArmed == armed) {
				// Check if a zone has been triggered
				if (keyValue == A || keyValue == B || keyValue == C) {
					triggered = 0;
					display(3);
					if (keyValue == A) {displayOr(8);}
					else if (keyValue == B) {displayOr(4);}
					else if (keyValue == C) {displayOr(2);}
					
					// Continue checking for the correct code entered until this code is entered
					while(triggered == 0) {
						triggered = correctCodeEntered2(currentCode);
					}
					
					// Re-arm system after correct code is entered
					flashLeds();
					sysArmed = armSystem();
					display(sysArmed);
				} 
				
				// Else check if the correct code is entered and disarm the system
				else {
					displayOr(keyValue);
					if(correctCodeEntered3(currentCode, keyValue) == 1) {
						// Arm the system
						sysArmed = disarmed;	
						flashLeds();
						display(sysArmed);
					}
				}
			
			
			// Else If the system is unarmed
			} else {
				// If hash entered, enter the change code mode
				if(keyValue == hash) {
					flashLeds();
					
					if(correctCodeEntered2(currentCode) == 1) {
						setNewCode(currentCode);
					}
					display(sysArmed);
					
				// If the correct code is entered, arm the system	
				} else {
					displayOr(keyValue);
					if(correctCodeEntered3(currentCode, keyValue) == 1) {
						// As system is currently disarmed, arm the system
						sysArmed = armed;
						flashLeds();
						display(sysArmed);
					}
				}
			}
		}
    }
}

// Flash all LEDs 4 times at a rate of 4Hz
void flashLeds() {
	for(int i = 0; i < 4; i++) {
		display(IDLE);
		delay();
		clearLEDs();
		delayHalf();
	}
}

/**
 * Initialize the relevant variables that will be used to reference registers
 */
void initialize() {
	ddrcio	= (uint8_t *) 0x34;
	pincio	= (uint8_t *) 0x33;
	portcio = (uint8_t *) 0x35;
	
	ddrbio	= (uint8_t *) 0x37;
	pinbio	= (uint8_t *) 0x36;
	portbio = (uint8_t *) 0x38;
	
	// Set the DDRC to input on the first 4 bits, and output on the second 4 bits
	*ddrcio		= 0xF0;

	// Enable the pullup resistors on the row inputs
	*portcio	= 0x0F;
	
	// Enable all the pull up resistors
	*portcio	= IDLE;
	
	// Configure all of port B to output and ensure the LEDs are off
	*ddrbio		= 0xFF;
	*portbio	= 0x00;
}

// Configure timer 0
void configTimer() {
	TCCR0 = 0x05;			// Reset the timer to the default state with /1024
	TCNT0 = 0x00;			// Reset the counter to 0x00
	TIFR = 0x00;			// Clear any pending interrupts
	TIMSK |= (1 << TOIE0);	// Set an interrupt on timer 0 
}

/**
 * Delay used to wait for the synchronizer to sync the input and output. This is a 0.25s delay
 */ 
void delay() {
	uint8_t count2 = 0;
	uint8_t count1 = 0;
	
	// This loop takes 0.25s
	while (count2 < 55) {
		count2++;
		// This inner loop takes 4.6ms
		while (count1 < IDLE) {
			count1++;
		}
	}
}

// A 0.5s delay
void delayHalf() {
	uint8_t count2 = 0;
	uint8_t count1 = 0;
	
	// This loop takes 0.5s
	while (count2 < 109) {
		count2++;
		// This inner loop takes 4.6ms
		while (count1 < IDLE) {
			count1++;
		}
	}
}

/**
 * Wait for the button on the keypad to be released
 */ 
uint8_t waitDebounce(uint8_t value) {
	volatile uint8_t val = value;
	
	// Continue looping until the button is released, 
	// hence changing the PINCIO value away from the initially pressed value
	while (val == value) {
		val = *pincio;
		delay();
	}
	return value;
}

/**
 * Reads the value of the keypad and returns it. If no button has been pressed, returns the idle value of 0xFF
 */ 
uint8_t readKP() {
	// Initialize the variables to be used
	uint8_t portVal = 0x00;
	uint8_t pressed = IDLE;
	// When this variable =1, a value has been found and hence break
	uint8_t found	= 0;
	
	// Search each column individually
	for (int i = 0; i < cols; i++) {
		// Break the loop if a value has been found
		if (found == 1) {break;}
		// Write the column mask to PORTC
		*portcio = colMasks[i];
		// Wait for the synchronizer to sync with the output
		delay();
		// Read the value on port c
		portVal = *pincio;
		
		// If a button in the current column is pressed, enter the if statement
		if (portVal != colMasks[i]) {
			// Wait for the debounce to occur and the button to be released
			waitDebounce(portVal);
			
			// Check the current hex value with each value in the relevant column of the lookup table
			for (int j = 0; j < rows; j++) {
				if (portVal == lookup[i][j]) {
					pressed = keypad[i][j];
					found = 1;
					break;
				}
			}
		}
	}
	return pressed;
}

/**
 * Displays the given value to the upper 4 bits of port B
 */ 
void displayOr(uint8_t value) {
	uint8_t x = *portbio;
	value = value << 4;
	
	*portbio = value | x;
	delay();
}

// Displays the given value to all 8 bits on port B
void display(uint8_t value) {
	*portbio = value;
	delay();
}

// Sets port B to 0x00;
void clearLEDs() {
	*portbio = 0;
	delay();
}

//Checks for the correct full 4 digit code is entered
// Return 0 for incorrect code, return 1 for correct code
uint8_t correctCodeEntered1(uint8_t currentCode[], uint8_t valueCheck[]) {
	uint8_t count = 0;
	uint8_t correctCode = 0;

	// Check if the first value in the array is idle; if so read the keypad into this element
	if (valueCheck[count] == IDLE) {
		valueCheck[count] = readKP();
		if (valueCheck[count] != IDLE) {
			displayOr(valueCheck[count]);
		}
	}
	// Check if the first value in the array is equal to the first value in the code
	if(valueCheck[count] == currentCode[count]) {
		count++;
		
		// Check if the second value in the array is idle; if so read the keypad into this element
		if (valueCheck[count] == IDLE) {
			valueCheck[count] = readKP();
			if (valueCheck[count] != IDLE) {
				displayOr(valueCheck[count]);
			}
		}
		// Check if the second value in the array is equal to the second value in the code
		if(valueCheck[count] == currentCode[count]) {
			count++;
			
			// Check if the third value in the array is idle; if so read the keypad into this element
			if (valueCheck[count] == IDLE) {
				valueCheck[count] = readKP();
				if (valueCheck[count] != IDLE) {
					displayOr(valueCheck[count]);
				}
			}				
			// Check if the third value in the array is equal to the third value in the code
			if(valueCheck[count] == currentCode[count]) {
				count++;
				
				// Check if the fourth value in the array is idle; if so read the keypad into this element
				if (valueCheck[count] == IDLE) {
					valueCheck[count] = readKP();
					if (valueCheck[count] != IDLE) {
						displayOr(valueCheck[count]);
					}
				}
				// Check if the fourth value in the array is equal to the fourth value in the code
				if(valueCheck[count] == currentCode[count]) {
					flashLeds();
					// Set the code as correct
					correctCode = 1;
				}
			}
		}
	}
	return correctCode;
}

/**
 * Takes in the current code array and checks for the entry of the 4 digits in the code
 * 		A 5 second timer is given to allow for the correct entry of digits
*/
uint8_t correctCodeEntered2(uint8_t currentCode[]) {
	timeout = 0;
	uint8_t correctCode = 0;
	uint8_t valueCheck[digits] = {IDLE, IDLE, IDLE, IDLE};
	TCCR0 = 0x05;	// Start timer 0 with a speed of /1024
	
	// Continue looping until the 5 second timeout is reached, or the correct code is entered
	while(timeout < 230 && correctCode == 0) {
		correctCode = correctCodeEntered1(currentCode, valueCheck);
	}
	timeout = 0;
	cli();

	return correctCode;
}

/**
 * Takes in the current code array and the already entered potential first digit, 
 * and checks for the entry of the remaining digits in the code
 * 		A 5 second timer is given to allow for the correct entry of digits
*/
uint8_t correctCodeEntered3(uint8_t currentCode[], uint8_t firstDigit) {
	timeout = 0;
	uint8_t correctCode = 0;
	uint8_t valueCheck[digits] = {firstDigit, IDLE, IDLE, IDLE};
	sei();
	TCCR0 = 0x05;		// Start timer 0 with a speed of /1024
	
	// Continue looping until the 5 second timeout is reached, or the correct code is entered
	while(timeout < 230 && correctCode == 0) {
		correctCode = correctCodeEntered1(currentCode, valueCheck);
	}
	timeout = 0;
	cli();

	return correctCode;
}

// Sets the system to an armed state
uint8_t armSystem() {
	clearLEDs();		// Turn the LEDs off
	
	delay();
	
	// Set 40 second delay
	uint8_t count = 0;
	
	// This loop takes 40 seconds
	while (count < 80) {
		count++;
		delayHalf();
	}	
	
	return 1;
}

// Sets a new code. Continues looping until 4 new digits are entered
void setNewCode(uint8_t currentCode[]) {
	uint8_t ledVal = IDLE;
	display(ledVal);		// Set all LEDs on
	uint8_t count = 0;
	
	// Delete the current code
	for (int i = 0; i < rows; i++) {
		currentCode[i] = IDLE;
	}
	
	// Keep looping until 4 new values have been entered
	while (count != rows) {
		// Read the keypad into the current value
		currentCode[count] = readKP();
		
		// If the keypad has been pressed, save this value and move to the next one
		if (currentCode[count] != IDLE) {
			displayOr(currentCode[count]);
			count++;			
		}
		
	}
}

// After 5 seconds, set the timeout flag
ISR (TIMER0_OVF_vect) {
	cli();				// Disable interrupt sources
	TCCR0 &= 0xF8;		// Stop timer 0
	TIFR |= 1 << TOV0;	// Clear the timer interrupt
	TCNT0 = 0x00;		// Reset the clock
	
	timeout = timeout +1; 	// Increment the timeout counter
	TCCR0 |= 0x05;			// Restart the clock	
	sei();					// Renable the interrupt sources
}
