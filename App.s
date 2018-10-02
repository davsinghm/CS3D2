; Definitions  -- references to 'UM' are to the User Manual.

stack_size equ 512

; Timer Stuff -- UM, Table 173
 
T0  equ 0xE0004000      ; Timer 0 Base Address
T1  equ 0xE0008000
 
IR  equ 0           ; Add this to a timer's base address to get actual register address
TCR equ 4
MCR equ 0x14
MR0 equ 0x18
 
TimerCommandReset   equ 2
TimerCommandRun equ 1
TimerModeResetAndInterrupt  equ 3
TimerResetTimer0Interrupt   equ 1
TimerResetAllInterrupts equ 0xFF
 
; VIC Stuff -- UM, Table 41
VIC equ 0xFFFFF000      ; VIC Base Address
IntEnable   equ 0x10
VectAddr    equ 0x30
VectAddr0   equ 0x100
VectCtrl0   equ 0x200
 
Timer0ChannelNumber equ 4   ; UM, Table 63
Timer0Mask  equ 1<<Timer0ChannelNumber  ; UM, Table 63
IRQslot_en  equ 5       ; UM, Table 58
 
IO1DIR  EQU 0xE0028018
IO1SET  EQU 0xE0028014
IO1CLR  EQU 0xE002801C
IO1PIN  EQU 0xE0028010
	
IO0DIR	equ	0xE0028008
IO0SET	equ	0xE0028004
IO0CLR	equ	0xE002800C

 
    AREA    InitialisationAndMain, CODE, READONLY
    IMPORT  main
 
; (c) Mike Brady, 2014–2016.
 
    EXPORT  start
start

; initialisation code

; initialize subroutine 1 stack
	ldr r0, =stack_sub1
	ldr r1, =stack_size
	add r0, r1
	add r0, #1
	ldr r1, =subroutine1
	stmfd r0!, {r1} ;initial val of pc
	stmfd r0!, {r0-r12, lr}
	ldr r1, =struct_sub1
	str r0, [r1]
	
; initialize subroutine 2 stack
	ldr r0, =stack_sub2
	ldr r1, =stack_size
	add r0, r1
	add r0, #1
	ldr r1, =subroutine2
	stmfd r0!, {r1} ;initial val of pc
	stmfd r0!, {r0-r12, lr}
	ldr r1, =struct_sub2
	str r0, [r1]

; Initialise the VIC
    ldr r0,=VIC         ; looking at you, VIC!
 
    ldr r1,=irqhan
    str r1,[r0,#VectAddr0]  ; associate our interrupt handler with Vectored Interrupt 0
 
    mov r1,#Timer0ChannelNumber+(1<<IRQslot_en)
    str r1,[r0,#VectCtrl0]  ; make Timer 0 interrupts the source of Vectored Interrupt 0
 
    mov r1,#Timer0Mask
    str r1,[r0,#IntEnable]  ; enable Timer 0 interrupts to be recognised by the VIC
 
    mov r1,#0
    str r1,[r0,#VectAddr]       ; remove any pending interrupt (may not be needed)
 
; Initialise Timer 0
    ldr r0,=T0          ; looking at you, Timer 0!
 
    mov r1,#TimerCommandReset
    str r1,[r0,#TCR]
 
    mov r1,#TimerResetAllInterrupts
    str r1,[r0,#IR]
 
    ldr r1,=(14745600/200)-1     ; 5 ms = 1/200 second
    str r1,[r0,#MR0]
 
    mov r1,#TimerModeResetAndInterrupt
    str r1,[r0,#MCR]
 
    mov r1,#TimerCommandRun
    str r1,[r0,#TCR]
 
;from here, initialisation is finished, so it should be the main body of the main program
 
	;b subroutine1
 
 
;main program execution will never drop below the statement above.
 
    AREA    InterruptStuff, CODE, READONLY
irqhan  sub lr, lr, #4
	
;this is the body of the interrupt handler
 
;here you'd put the unique part of your interrupt handler
;all the other stuff is "housekeeping" to save registers and acknowledge interrupts

	stmfd   sp!, {r0-r1}
	
	;increment the timeval
	ldr r0, =timeval
	ldr r1, [r0]
	add r1, #5
	str r1, [r0]
	
	;this is where we stop the timer from making the interrupt request to the VIC
	;i.e. we 'acknowledge' the interrupt
    ldr r0, =T0
    mov r1, #TimerResetTimer0Interrupt
    str r1, [r0,#IR]     ; remove MR0 interrupt request from timer
 
	;here we stop the VIC from making the interrupt request to the CPU:
    ldr r0, =VIC
    mov r1, #0
    str r1, [r0,#VectAddr]   ; reset VIC
	
	;check which thread is running
	ldr r0, =thread_no
	ldr r1, [r0]
	mov r0, #0 ;r1 = [thread_no]
	cmp r0, r1
	beq dispatch_subroutine ;no thread is running, jump to dispatching
	;no thread is running. initialize:
	
	

stash_subroutine

	;ldr r0, =struct_sub1
	;ldr r1, [r0, #0]       ; load stack pointer
	mov r1, lr             ; r1 = pc of current program
	;load
	msr cpsr_c, #&1f       ; sys mode
	stmfd sp!, {r1}        ; push pc on stack
	msr cpsr_c, #&12       ; irq mode
	ldmfd sp!, {r0-r1}     ; load regs from irq stack
	msr cpsr_c, #&1f       ; sys mode
	stmfd sp!, {r0-r12,lr} ; push all regs and lr
	
	mov r1, sp             ;move stack pointer to r1 TODO
	msr cpsr_c, #&12       ; irq mode
	;save stack pointer to current subroutines struct
	;TODO decide the struct based on thread_no
	ldr r0, =struct_sub1
	str r1, [r0, #0]       ; save stack pointer to struct
	mrs r1, spsr
	str r1, [r0, #4]       ; save spsr to struct

dispatch_subroutine

init_sub1
	mov r1, #1
	ldr r0, =thread_no
	str r1, [r0] ;temp, put 1 in thread_no
;	sub sp, #4
	ldr r0, =struct_sub1
	ldr r1, [r0, #0]              ; load stack pointer
	ldr r2, [r0, #4]              ; load stored cpsr
	msr spsr_cxsf, r2
	mov r0, lr                    ; r0 = pc of current program
	msr cpsr_c, #&1f              ; sys mode
	mov sp, r1                    ; change stack pointer
	msr cpsr_c, #&1f              ; user mode TODO
	ldmfd sp!, {r0-r12, lr, pc}^   ; load all regs from stack + pc
 
    AREA    Subroutines, CODE, READONLY

subroutine1
	; initializing gpio
    ldr r1, =IO1DIR
    ldr r2, =0x000f0000  ; select P1.19--P1.16
    str r2, [r1]     ; make them outputs
    ldr r1, =IO1SET
    str r2, [r1]     ; set them to turn the LEDs off
    ldr r2, =IO1CLR
    ; resv:
	; r0 = 1000 + val(timeval)
    ; r1 = IO1SET
    ; r2 = IO1CLR
	; r3 = timeval
    ; r4 = current led bit
led_start_bit equ 0x00010000
led_end_bit equ 0x00100000
    ldr r4, =led_start_bit ;p16
 
    ldr r3, =timeval
    ldr r0, [r3]
    ldr r5, =1000
    add r0, r5

wloop_sec
    ldr r5, [r3]
    cmp r0, r5
    bgt wloop_sec ; changed from bne
 
    ; turn led on
    ldr r5, =0x000f0000
    str r5, [r1] ; set the bit -> turn off the LED
    str r4, [r2] ; clear the bit -> turn on the LED
    mov r4, r4, lsl #1
	; check led bounds
    ldr r5, =led_end_bit
    cmp r4, r5
    bne fi_reset_led
    ldr r4, =led_start_bit ; reset led bit
fi_reset_led
    add r0, #1000   ; add 1000
    b wloop_sec       ; branch always

subroutine2
	ldr r0, =IO0DIR
	ldr r1, =0x0000ff00
	str r1, [r0]
	ldr r5, =IO0CLR
	ldr r2, =IO0SET
	mov r4, #60	;i
	
	ldr r0, =seg_lt
wloop_seg
	;bge fi_i ; if r4 < 0 -> r4 = 0
	ldr r4, =60
fi_i
	str r1, [r5] ; clear bits
	ldr r3, [r0, r4]  ; temp lookup table val
	str r3, [r2]
	bl delay
	subs r4, #4
	b wloop_seg

delay
	stmfd sp!, {r0}
	ldr r0, =10000000
do_delay
	subs r0, #1
	bne do_delay ; while (r0 != 0)
	ldmfd sp!, {r0}
	bx lr
 
    AREA    Stuff, DATA, READWRITE

timeval
	dcd 0
	
; lookup table for 7seg display
seg_lt
	dcd	0x3F00, 0x0600
	dcd 0x5B00, 0x4F00
	dcd 0x6600, 0x6D00
	dcd 0x7D00, 0x0700
	dcd 0x7F00, 0x6F00
	dcd 0x7700, 0x7C00
	dcd 0x3900, 0x5E00
	dcd 0x7900, 0x7100

struct_sub1
	dcd 0x00 ;stack pointer
	dcd 0x00 ;cpsr
	dcd 0x00 ;
struct_sub2
	dcd 0x00 ;stack pointer
	dcd 0x00 ;cpsr
	dcd 0x00 ;

stack_sub1
	space stack_size
stack_sub2
	space stack_size
	
thread_no
	dcd 0x00

	end