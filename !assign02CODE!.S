#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                                         @ Specify unified assembly syntax
.cpu    cortex-m0plus                                   @ Specify CPU type is Cortex M0+
.thumb                                                  @ Specify thumb assembly for RP2040
.global main_asm                                        @ Provide program starting address to the linker
.align 4                                                @ Specify code alignment

.extern timeus											@ External time function to get time in us
.extern inputComplete

.equ    DFLT_ALARM_TIME, 4000000                        @ Specify the default alarm timeout

.equ    GPIO_BTN, 21                                    @ Specify button 21 as input
.equ    GPIO_BTN_RISE_MASK, 0x00400000                  @ Specify bit 22 for rising edge event on GPIO 21 (From rp2040 datasheet sec 2.19)
.equ    GPIO_BTN_FALL_MASK, 0x00800000                  @ Specify bit 23 for falling edge event on GPIO 21 (From rp2040 datasheet sec 2.19)
.equ    GPIO_DIR_IN,   0                                @ Specify direction of input a GPIO pin
.equ    GPIO_DIR_OUT,  1                                @ Specify direction of output a GPIO pin

.equ    GPIO_ISR_OFFSET, 0x74                          
.equ    ALRM_ISR_OFFSET, 0x40                           

.equ    DOT, 300000                                     @ Max time in us for dot input
.equ    DASH, 1000000                                   @ Max time in us for dash input
.equ    SPCE, 3000000                                   @ Max time in us for space input

main_asm:
    push    {lr}				  @ Store the link register to the stack
    bl      install_gpio_isr      @ Initialize GPIO interrupt
    bl      install_alrm_isr      @ Initialize Alarm interrupt
    bl      init_btns             @ Initialize the button
    bl      set_alrm              @ Set initial alarm for seconds
    
    @ Initialize input_flag to 0
    ldr     r0, =input_flag
    movs    r1, #0
    str     r1, [r0]
    
    pop     {pc}				  @ Pop the link register from the stack to the program counter
main_loop:
    wfi                           @ Wait for interrupt
    b       main_loop             @ Loop back again waiting for interrupt

init_btns:
    push    {lr}                                        @ Store the link register to the stack

    movs    r0, #GPIO_BTN                               @ Move pin number to r0 for init to use
    bl      asm_gpio_init                               @ Call the subroutine to initialise the button pin 
    movs    r0, #GPIO_BTN                               @ Move pin number to r0 for set_dir to use
    movs    r1, #GPIO_DIR_IN                            @ Set direction of pin as 0, ie. input
    bl      asm_gpio_set_dir                            @ Call the subroutine to set direction of button pin
    movs    r0, #GPIO_BTN                               @ Move pin number to r0 for set_irq to use
    bl      asm_gpio_set_irq                            @ Call the subroutine to enable rising and falling-edge interrupts for button pin

    pop     {pc}                                        @ Pop the link register from the stack to the program counter

############################################################################################
@ Set New Alarm
set_alrm:
	push    {r1-r3, lr}									@ Store the link register and registers to the stack

	ldr     r0, =1            							@ Load value 1 
	ldr     r1, =(TIMER_BASE + TIMER_INTE_OFFSET)  		@ Get address of interrupt enable register
	str     r0, [r1]          							@ Store 1 to enable alarm0 interrupt

	ldr     r0, =DFLT_ALARM_TIME 					 	@ Load default timeout value in us
	ldr     r2, =TIMER_BASE       						@ Load Timer peripheral base address
	ldr     r1, [r2, #TIMER_TIMELR_OFFSET] 				@ Get current time (lower 32 bits)
	adds    r1, r0                						@ Add timeout to current time
	str     r1, [r2, #TIMER_ALARM0_OFFSET] 				@ Set alarm0 to trigger at calculated time

	pop     {r1-r3, pc}      							@ Pop the link register and other registers from the stack

install_alrm_isr:
    ldr     r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)        @ Get address of vector table from VTOR register
    ldr     r1, [r2]                                    @ Load the base address of the vector table
    movs    r2, #ALRM_ISR_OFFSET                        @ Get the ALRM_ISR_OFFSET in vector table
    add     r2, r1                                      @ Calculate exact address in vector table for ALARM0 handler
    ldr     r0, =alrm_isr                               @ Load address of alarm ISR
    str     r0, [r2]                                    @ Store ISR address in vector table at ALARM0 position
    
    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)   @ Get address of interrupt clear-pending register
    ldr     r1, =1                                      @ Prepare value with bit 0 set
    str     r1, [r2]                                    @ Clear any pending ALARM0 interrupts
    
    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)   @ Get address of interrupt set-enable register
    ldr     r1, =1                                      @ Prepare value with bit 0 set
    str     r1, [r2]                                    @ Enable ALARM0 interrupt in NVIC
    
    bx      lr                                          @ Return to caller

############################################################################################
@ Servicing the Alarm ISR
.thumb_func                             
alrm_isr:
    push    {r0-r3, lr}                    @ Store the link register and registers to the stack
    
    @ Clear interrupt
    ldr     r0, =1                         @ Load value 1 (for ALARM0 bit)
    ldr     r1, =(TIMER_BASE + TIMER_INTR_OFFSET)  @ Get address of interrupt status register
    str     r0, [r1]                       @ Write 1 to clear the ALARM0 interrupt flag
    
    @ Check if there have been other inputs before sending code 4
    ldr     r2, =input_flag
    ldr     r2, [r2]
    cmp     r2, #0
    beq     alrm_exit                      @ If no inputs yet, skip sending code 4
    
    movs    r0, #4                         @ Load argument 4 (end sequence code)
    bl      user_input                     @ Call user_input function
    
    @ Reset the input flag after sending code 4
    ldr     r2, =input_flag
    movs    r3, #0
    str     r3, [r2]

alrm_exit:
	pop     {r0-r3, pc}		@ Pop the link register and other registers from the stack

install_gpio_isr:
    ldr     r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)   @ Get address of vector table from VTOR register
    ldr     r1, [r2]                               @ Load the base address of the vector table
    movs    r2, #GPIO_ISR_OFFSET                   @ Get the offset for GPIO IRQ in vector table
    add     r2, r1                                 @ Calculate exact address in vector table for GPIO handler
    ldr     r0, =gpio_isr                          @ Load address of GPIO ISR
    str     r0, [r2]                               @ Store ISR address in vector table at GPIO position
    
    ldr     r0, =0x1                               		@ Load value 1
    lsls    r0, #13                               		@ Shift left by 13 positions
    ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)   @ Get address of interrupt clear-pending register
    str     r0, [r1]                               		@ Clear any pending GPIO interrupts
    
    ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)   @ Get address of interrupt set-enable register      
    str     r0, [r1]                               		@ Enable GPIO interrupt in NVIC
    
    bx      lr                                     		@ Return to caller

.thumb_func                            
gpio_isr:
    push    {r0-r7, lr}                    @ Store the link register and registers to the stack
    
    @ Get interrupt status
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)  	@ Load address of GPIO interrupt status register
    ldr     r1, [r2]                       					@ Read current interrupt status
    
    @ Check for rising edge
    ldr     r0, =GPIO_BTN_RISE_MASK        @ Load mask for rising edge on GPIO
    tst     r1, r0                         @ Test if rising edge bit is set
    bne     handle_rising_edge             @ If rising edge detected, branch to handler for it
    
    @ Check for falling edge
    ldr     r0, =GPIO_BTN_FALL_MASK        @ Load mask for falling edge on GPIO 21 (bit 23)
    tst     r1, r0                         @ Test if falling edge bit is set
    bne     handle_falling_edge            @ If falling edge detected, branch to handler for it
    
    b       gpio_clear_and_exit            @ If neither, exit

handle_rising_edge:
    bl      timeus 					@ Get start time of button push
    ldr     r4, =start_time			@ Get address of start_time and put in r4
    str     r0, [r4]				@ Store time value in start_time
    b       gpio_clear_and_exit 	@ Exit 

handle_falling_edge:
    bl      timeus					@ Get end time of button push
    movs    r5, r0                	@ Save that time in r5
    ldr     r4, =start_time			@ Get address of start_time and put in r4
    ldr     r6, [r4]              	@ Load start time into r6
    subs    r6, r5, r6            	@ Get time difference, ie. how long button was pressed

    @ Reset alarm timer
    bl      set_alrm              	@ Reset alarm after button press dealt with

    ldr     r7, =DOT	@ If time diff is less than that required for dash
    cmp     r6, r7
    blt     add_dot		@ Add dot 

    ldr     r7, =DASH	@ If it is gretaer than dot but less than dash
    cmp     r6, r7
    blt     add_dash	@ Add dash

    ldr     r7, =SPCE	@ If it is greather than dash
    cmp     r6, r7
    blt     add_space	@ Add space

add_dot:
    @ Set input flag to indicate there's been an input
    ldr     r7, =input_flag
    movs    r5, #1
    str     r5, [r7]
    
    ldr    	r0, =1         			@ Code for dot
    bl      user_input				@ Brance to user_input with code 1 for dot 
    b       gpio_clear_and_exit

add_dash:
    @ Set input flag to indicate there's been an input
    ldr     r7, =input_flag
    movs    r5, #1
    str     r5, [r7]
    
    ldr    	r0, =2          		@ Code for dash
    bl      user_input				@ Brance to user_input with code 2 for dash 
    b       gpio_clear_and_exit

add_space:
    @ Set input flag to indicate there's been an input
    ldr     r7, =input_flag
    movs    r5, #1
    str     r5, [r7]
    
    ldr    	r0, =3       			@ Code for space
    bl      user_input				@ Brance to user_input with code 3 for space 
    b       gpio_clear_and_exit

gpio_clear_and_exit:
    @ Clear GPIO interrupt
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)
    ldr     r0, =(GPIO_BTN_RISE_MASK | GPIO_BTN_FALL_MASK)
    str     r0, [r2]
    
    @ Clear NVIC interrupt
    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
    ldr     r0, =0x2000
    str     r0, [r2]
    
    pop     {r0-r7, pc}		@ Pop the link register and other registers from the stack

.data
start_time: .word   0
input_flag: .word   0         @ Flag to track if there have been inputs