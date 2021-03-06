# --------------------------------------------------------------
#      Author: Samuel Cuthbertson
#  Assignment: homework4  <change N to the appropriate value>
#        Date: 11/5/2017
#      System: DE10-Lite PDS Computer
# Description: Counts using interrupts while also displaying a night-rider
#								slide on the LEDS. Displays count in decimal 0-99 on HEX0/1,
#								logs count rolling over to UART.
# Attribution: Some pieces copied verbatim from class examples.
# --------------------------------------------------------------

		# ---------------------------------------------------------
		# RESET SECTION
		# ---------------------------------------------------------
        # The Monitor Program places the ".reset" section at the reset location
        # specified in the CPU settings in Qsys.
        # Note: "ax" is REQUIRED to designate the section as allocatable and executable.


		# A real reset handler would fully initialize the CPU and then jump to start.
		# CPU's reset vector = 0x0000_0000
        .section    .reset, "ax"

reset:
        movia       r2, _start
        jmp         r2



		# ---------------------------------------------------------
		# EXCEPTION SECTION
		# ---------------------------------------------------------
        # The Monitor Program places the ".exceptions" section at the
        # exception location specified in the CPU settings in Qsys.
        # Note: "ax" is REQUIRED to designate the section as allocatable and executable.

		# CPU's exception vector = 0x0000_0020
        .section    .exceptions, "ax"

exception_handler:
		jmpi 		interrupt_service_routine





		# ---------------------------------------------------------
		# TEXT SECTION
		# ---------------------------------------------------------
		.text

		.include 	"address_map_nios2.s"
    .equ		DELAY_VALUE, 150000
		.global 	_start

_start:

		# Nios II register usage convention
		#      r1     : assembler temporary, don't use this!
		#   r2-r3     : output from subroutine
		#   r4-r7     : input to subroutine
		#   r8  - r15 : Caller saved.
		#   r16 - r23 : Callee saved.
		#   r24 - r31 : Reserved/special function registers, stack pointer
		#               return address etc., don't use these as general
		#               purpose registers in the code you write!

# --------------------------------------------------------------
# Initialization code
# --------------------------------------------------------------
		# IMPORTANT: Set up the stack frame.
		# This is required if you will be calling subroutines/functions
		movia 	sp, SDRAM_CTRL_END
		movia 	fp, SDRAM_CTRL_END

		# main program initialization steps
    movia		r8, LED_OUT_BASE
    movia 	r11, 0b0000000001 # Initial led pattern
    mov		  r12, r0 # Initial move direction


# --------------------------------------------------------------
# Insert your ISR initialization code here
# --------------------------------------------------------------

		# ---------------------------------------------------
        # Configure devices to generate interrupts
		# ---------------------------------------------------
		# enable timer to create an IRQ to the CPU
    movia       r15, TIMER_BASE

		movia 			r7, time_delayl
		ldw         r6, (r7)
   	sthio       r6, 0x8(r15) # Set the periodl reg

		movia 			r7, time_delayh
		ldw         r6, (r7)
   	sthio       r6, 0xC(r15) # Set the periodh reg

		movia       r6, 0b0101
    stbio       r6, 0x4(r15) # Set the status to 101: start, do cont, do IQR


		# ---------------------------------------------------
		# Configure CPU to take external hardware interrupts
		# ---------------------------------------------------

		# Enable input on irq[1]
		movia				r7, IRQ_TIMER_MASK
		wrctl				ienable, r7

		# Set status[PIE] to enable the CPU
		movi				r7, 0b0001
		wrctl				status, r7

		/* ----------------------------------------------------------
		 * Finish initialization
		---------------------------------------------------------- */

		/* Display the lower 4-bits of the count value on HEX0 */
		/* We "cheat" because we know its assembled to 0. See count: .word below */
		movia		   r4, segement_table 	/* r4 -> segment table base */
		mov  		   r5, r0               /* initial count value */
		add			   r4, r4, r5          /* point (offset) to char code in table */
		ldbu		   r5, (r4)            /* get the char code from the table */
		slli			 r7, r5, 0x8 				 # Use that for the upper digit
		ldbu		   r5, (r4)            /* get the char code from the table */
		add 			 r5, r7, r5					 # Add both digits, store in r5
		movia		   r4, SEGA_OUT_BASE   /* r4 -> HEX0 base */
		stwio		   r5, (r4)            /* write the value to HEX0 */




# --------------------------------------------------------------
# main program
# --------------------------------------------------------------
loop:
		# Write our current pattern to the LEDs
		stwio		r11, (r8)

		# Wait, use a simple count down
		movia		r10, DELAY_VALUE

delay_loop1:
		subi		r10, r10, 1 # Decrement counter
		bne			r10, r0, delay_loop1 # Repeat if we're still waiting

		# Change pattern
		br      slide

slide:
		bne     r0, r12, slide_down # Are we in the down mode?

		movia		r13, 0b1000000000 # Max led pattern

		beq     r13, r11, slide_down # Should we now be in the down mode?

		slli    r11, r11, 0b1 # Shift left one LED

		br      loop

slide_down:
		movia   r12, 0b1 # Set the mode

		srli    r11, r11, 0b1 # Shift right one LED

		movia		r13, 0b1 # Min led pattern

		bne     r13, r11, loop # If we should still be going right, repeat

		movia   r12, 0b0 # Else, set the mode

    br      loop

# --------------------------------------------------------------
# End of main program
# --------------------------------------------------------------

# ------------------------------------------------------------
# print ()
# Takes as argument string pointed to by r4, prints to UART.
#
print:
				movia 			r16, UART_BASE
				ldwio				r17, 4(r16)         # Is there space available in the TX FIFO?
				andhi   		r17, r17, 0xFFFF    # Only look at the upper 16-bits.
				beq					r17, r0, print 		  # No space, wait for space to become available.

				# OK, there is space in the TX FIFO, send the character to the host
				ldb					r17, (r4)							# Load our character to be sent

				beq 				r0, r17, _print_ret		# If null, return. End of string


				stbio				r17, (r16)						# Else, send character

				# Iterate
				addi				r4, r4, 0x1
				br					print

_print_ret:
				ret




# ---------------------------------------------------------
# Exception Handler / Interrupt Service Routine
# ---------------------------------------------------------
interrupt_service_routine:

		# Adjust the size of the stack frame as needed by your code
		.equ		ISR_STACKSIZE,	9*4 		# 7 32-bit words

        # make a stack frame
        subi        sp, sp, ISR_STACKSIZE

        # ---------------------------------
        # save the registers we use in here
        # ---------------------------------
        stw         et,  0(sp)

        # check for internal vs. external IRQ
        # decrement ea for external IRQ
        rdctl       et, ipending    # get all 32 bits that represent irq31 to irq0
        beq         et, r0, skip_ea_dec

        subi        ea, ea, 4       # must decrement ea by one instruction
                                    # for external interrupts, so that the
                                    # interrupted instruction will be run after eret
skip_ea_dec:
        stw         ea,  4(sp)		# save the exception address
        stw         ra,  8(sp)		# save the current subrountine's ra
        stw         r4,  12(sp)		# save the registers we use in this routine
        stw         r5,  16(sp)
        stw         r6,  20(sp)
        stw         r7,  24(sp)

        stw         r16,  28(sp)  # used by print
        stw         r17,  32(sp)

		# bail if IRQ is not external hardware interrupt
        beq         et, r0, end_isr     # interrupt is not external IRQ

		# Determine source of the interrupt - can only be the timer in this example

		# Service the interrupting device
		/* update the count in memory         */
				movia       r4, count           # r4 -> mmory location that holds the count variable
				ldw         r5, (r4)            # fetch the count from ememory
				addi        r5, r5, 0x1      		# increment the count

				andi				r6, r5, 0x0F				# See if lower count is 10
				movia				r7, 0xA
				bne					r7, r6, do_display  # If it's not, just update display


				movia       r4, count						# First Digit is 10
				ldw         r5, (r4)            # fetch the count from ememory
				andi				r6, r5, 0xF0				# Update higher count
				srli				r6, r6, 0x4
				addi				r6, r6, 0x1					# increment
				slli				r5, r6, 0x4
				movia				r7, 0xA							# See if upper digit is 10
				bne					r7, r6, do_display

				# They're both 10! Roll over
				movia				r5, 0x00
				movia				r4, counter_str
				call 				print

do_display:
				movia       r4, count           # r4 -> mmory location that holds the count variable
				stw         r5, (r4)            # store the count back to memory

		/* display the lower 4-bits of the 32-bit count value on HEX0 */
				movia				r4, segement_table 	/* r4 -> segment table base */
				andi				r5, r5, 0x000F
				add					r4, r4, r5          /* r4 -> point (offset) to char code in table */
				ldbu				r5, (r4)            /* get the char code from the table */
				# Let's save the lower bits in r7
				mov 				r7, r5

		/* display the lower 4-bits of the 32-bit count value on HEX0 */
				movia       r4, count           # r4 -> mmory location that holds the count variable
				ldw         r5, (r4)            # fetch the count from ememory
				movia				r4, segement_table 	/* r4 -> segment table base */
				andi				r5, r5, 0x00F0
				srli				r5, r5, 0x4
				add					r4, r4, r5          /* r4 -> point (offset) to char code in table */
				ldbu				r5, (r4)            /* get the char code from the table */

				slli				r5, r5, 0x8					# put upper digit in place
				add					r5, r5, r7					# combine digits

				movia				r4, SEGA_OUT_BASE   /* r4 -> HEX0 base */
				stwio				r5, (r4)            /* write the HEX0 */


		# Clear the source of the interrupt
        movia       r5, TIMER_BASE
        movia       r6, 0b00
        stwio       r6, (r5)

		# Restart the timer
				movia       r6, 0b0101
				stbio       r6, 0x4(r5) # Set the status to 101: start, do cont, do IQR

end_isr:
        # restore registers we used
        ldw         et,  0(sp)
        ldw         ea,  4(sp)
        ldw         ra,  8(sp)
        ldw         r4, 12(sp)
        ldw         r5, 16(sp)
				ldw					r6, 20(sp)
				ldw         r7, 24(sp)

				ldw         r16,  28(sp)  # used by print
        ldw         r17,  32(sp)

        # free the stack frame
        addi        sp, sp, ISR_STACKSIZE


		eret		# return from exception


		# ---------------------------------------------------------
		# DATA SECTION
		# ---------------------------------------------------------
		.data
		    				.align 		2	# align to 2^2=4 byte boundary

counter_str:		.ascii		"The counter has rolled over\n\0\0\0" # Extra nulls b/c of align

time_delayl:  	.word   	0x9680 # Magic value -> 1/4 sec interrupts
time_delayh:		.word			0x0098


# A global variable used by the interrupt service routine.
# Main code (ie _start code) should NEVER write this location !!!
count:  .word       0x00 /* memory location that holds the current count */


/* ------------------------------------------------- */
/* 7-segment display character code table */
/* This is another example of how the assembler can be */
/* used to build a control table in memory */
segement_table:
		.byte					0x3F /* 0 */
		.byte					0x06 /* 1 */
		.byte					0x5B /* 2 */
		.byte					0x4F /* 3 */

		.byte					0x66 /* 4 */
		.byte		  		0x6D /* 5 */
		.byte					0x7D /* 6 */
		.byte					0x07 /* 7 */

		.byte					0x7F /* 8 */
		.byte					0x67 /* 9 */
		.byte					0x77 /* A */
		.byte					0x7C /* b */

		.byte					0x39 /* C */
		.byte					0x5E /* d */
		.byte					0x79 /* E */
		.byte					0x71 /* F */


		.end		# end of assembly.
