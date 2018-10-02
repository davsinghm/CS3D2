; Definitions  -- references to 'UM' are to the User Manual.

stack_size         equ 512
struct_size        equ 0x08
struct_offset_sp   equ 0x00
	
led_start_bit      equ 0x00010000
led_end_bit        equ 0x00100000

; Timer Stuff -- UM, Table 173
 
T0     equ 0xE0004000      ; Timer 0 Base Address
T1     equ 0xE0008000
 
IR     equ 0           ; Add this to a timer's base address to get actual register address
TCR    equ 4
MCR    equ 0x14
MR0    equ 0x18
 
TimerCommandReset           equ 2
TimerCommandRun             equ 1
TimerModeResetAndInterrupt  equ 3
TimerResetTimer0Interrupt   equ 1
TimerResetAllInterrupts     equ 0xff
 
; VIC Stuff -- UM, Table 41
VIC         equ 0xfffff000      ; VIC Base Address
IntEnable   equ 0x10
VectAddr    equ 0x30
VectAddr0   equ 0x100
VectCtrl0   equ 0x200
 
Timer0ChannelNumber equ 4   ; UM, Table 63
Timer0Mask  equ 1 << Timer0ChannelNumber  ; UM, Table 63
IRQslot_en  equ 5       ; UM, Table 58
 
IO1DIR      equ 0xE0028018
IO1SET      equ 0xE0028014
IO1CLR      equ 0xE002801C
IO1PIN      equ 0xE0028010

IO0DIR      equ 0xE0028008
IO0SET      equ 0xE0028004
IO0CLR      equ 0xE002800C

 
    AREA    InitialisationAndMain, CODE, READONLY
    IMPORT  main
 
; (c) Mike Brady, 2014–2016.
; (c) Davinder Singh, 2018.
 
; questions.
; 1. changing the user mode in initialization of struct speedup the process. why?
; 2. what are fields in msr, c x s f?
; 3. what is { cond } in every instruction
; 4. what is & in front of number?
; 5. can we acknowledge the interrupt in very beginning of handler?
; 6. why do we need to save original lr for each subroutine?
; 7. why does the order or reg list in stm matter? or does it?
    EXPORT  start
start

; initialisation code
    ; initialize subroutine 1 struct
    ldr r0, =stack_sub1
    ldr r1, =stack_size
    add r0, r1
    add r0, #1
    ldr r1, =subroutine1
    stmfd r0!, {r1}                 ; push initial val of pc
    stmfd r0!, {lr}
    sub r0, #13*4                     ; r0 to r12, 13 * 4 bytes
;    stmfd r0!, {r0-r12, lr}         ; TODO just increase/decrese sp instead?	
    mrs r1, cpsr                    ; load cpsr
    bic r1, #&1f                    ; clear the mode bits
    orr r1, #&10                    ; set mode to user
    stmfd r0!, {r1}                 ; push cpsr val to stack
    ldr r1, =struct_sub1
    str r0, [r1, #struct_offset_sp] ; save the sp to stack
    
    ; initialize subroutine 2 struct
    ldr r0, =stack_sub2
    ldr r1, =stack_size
    add r0, r1
    add r0, #1
    ldr r1, =subroutine2
    stmfd r0!, {r1}
    stmfd r0!, {lr}
    sub r0, #13*4
    mrs r1, cpsr
    bic r1, #&1f
	orr r1, #&10
    stmfd r0!, {r1}
    ldr r1, =struct_sub2
    str r0, [r1, #struct_offset_sp]

    ; Initialise the VIC
    ldr r0, =VIC                    ; looking at you, VIC!
 
    ldr r1, =irqhan
    str r1, [r0, #VectAddr0]        ; associate our interrupt handler with Vectored Interrupt 0
 
    mov r1, #Timer0ChannelNumber+(1<<IRQslot_en)
    str r1, [r0, #VectCtrl0]        ; make Timer 0 interrupts the source of Vectored Interrupt 0
 
    mov r1, #Timer0Mask
    str r1, [r0, #IntEnable]        ; enable Timer 0 interrupts to be recognised by the VIC
 
    mov r1, #0
    str r1, [r0, #VectAddr]         ; remove any pending interrupt (may not be needed)
 
    ; Initialise Timer 0
    ldr r0, =T0                     ; looking at you, Timer 0!
 
    mov r1, #TimerCommandReset
    str r1, [r0, #TCR]
 
    mov r1, #TimerResetAllInterrupts
    str r1, [r0, #IR]
 
    ldr r1, =(14745600/200)-1      ; 5 ms = 1/200 second
    str r1, [r0, #MR0]
 
    mov r1, #TimerModeResetAndInterrupt
    str r1, [r0, #MCR]
 
    mov r1, #TimerCommandRun
    str r1, [r0, #TCR]
 
;from here, initialisation is finished, so it should be the main body of the main program
    
 
;main program execution will never drop below the statement above.
 
wloop_main
    b wloop_main
 
    AREA    InterruptStuff, CODE, READONLY
irqhan  sub lr, lr, #4
    
;this is the body of the interrupt handler
 
;here you'd put the unique part of your interrupt handler
;all the other stuff is "housekeeping" to save registers and acknowledge interrupts

    stmfd   sp!, {r0-r2}
    
    ;increment the timeval
    ldr r0, =timeval
    ldr r1, [r0]
    add r1, #5
    str r1, [r0]
    
    ; this is where we stop the timer from making the interrupt request to the VIC
    ; i.e. we 'acknowledge' the interrupt
    ldr r0, =T0
    mov r1, #TimerResetTimer0Interrupt
    str r1, [r0,#IR]                 ; remove MR0 interrupt request from timer
 
    ; here we stop the VIC from making the interrupt request to the CPU:
    ldr r0, =VIC
    mov r1, #0
    str r1, [r0,#VectAddr]           ; reset VIC
    
    ; check which thread is running
    ldr r1, =struct_pt
    ldr r0, [r1]       ; NOW, r0 = [struct_pt]
    ldr r1, =struct_pt_end    ; =struct_nums means nothing is running, TODO should be -1
    cmp r0, r1
    beq dispatch_subroutine ; no thread is running, jump to dispatching    

stash_subroutine

    msr cpsr_c, #&1f       ; sys mode
    mov r1, sp             ; r1 = subroutine's stack pointer
    mov r2, lr             ; r2 = subroutine's link reg
    msr cpsr_c, #&12       ; irq mode
                      ; NOW, r1 = sp of subroutine
    stmfd r1!, {lr}        ; push pc of subroutine on stack
    stmfd r1!, {r2}        ; push lr of regs
    stmfd r1!, {r3-r12}    ; push all regs and lr
    ldmfd sp!, {r3-r5}     ; load regs from irq stack
    stmfd r1!, {r3-r5}     ; push all regs and lr
    mrs r2, spsr           ; load spsr
    stmfd r1!, {r2}        ; push spsr to stack
    
    ; save stack pointer to current subroutines struct
                      ; NOW, all reg r2+ are free
	

    ;ldr r3, =struct_pt
	;add 
    ;ldr r3, =struct_size
    ;mul r2, r3, r0         ; r2 = struct_size x struct_pt
    ;ldr r3, =struct_pt
	;ldr r2, [r3]
    ;add r2, r3             ; r2 = struct_pt + struct_size
	; as r0 is pointer to struct
    str r1, [r0, #struct_offset_sp] ; save stack pointer to struct
                      ; NOW, r1 is free

    ; r0 = [struct_index]
    ; r2 = struct_subX

dispatch_subroutine

    ; goto next subroutine struct in list
    add r0, #struct_size             ; add 1 to struct_pt
    ldr r2, =struct_pt_end
    cmp r0, r2
    blt fi_reset_pt
    ldr r0, =struct_pt_start  ; reset index to 1
fi_reset_pt
    ; store value of struct index
    ldr r1, =struct_pt
    str r0, [r1]

    ;ldr r3, =struct_size
    ;mul r2, r3, r0         ; r2 = struct_size x struct_index
    ;ldr r3, =struct_pt_start
    ;add r2, r3             ; r2 = struct_start + (offset = struct_index * struct_size)
	;mov r0, r2

    ldr r1, [r0, #struct_offset_sp] ; load stack pointer
    ldmfd r1!, {r3}                 ; pop spsr value from stack
    msr spsr_c, r3                  ; mov to spsr reg
    msr cpsr_c, #&1f                ; sys mode
    mov sp, r1                      ; change stack pointer
    ldmfd sp!, {r0-r12, lr, pc}^    ; load all regs from stack + pc



    AREA    Subroutines, CODE, READONLY

; @subroutine1: turns on led from p1.16 to p1.19 in sequence when one second elapses
subroutine1
    ; initializing gpio
    ldr r1, =IO1DIR
    ldr r2, =0x000f0000         ; select p1.19 - p1.16
    str r2, [r1]                ; make them outputs
    ldr r1, =IO1SET
    str r2, [r1]                ; set them to turn the LEDs off
    ldr r2, =IO1CLR
                           ; NOW:
                                ; r0 = 1000 + val(timeval)
                                ; r1 = IO1SET
                                ; r2 = IO1CLR
                                ; r3 = timeval
                                ; r4 = current led bit
    ldr r4, =led_start_bit      ; which is p1.16
    ldr r3, =timeval
    ldr r0, [r3]
    ldr r5, =1000
    add r0, r5

wloop_sec
    ldr r5, [r3]
    cmp r0, r5
	; TODO gives up the cpu here
	;swi #4
    bgt wloop_sec            ; changed from bne to bgt, cause cpu might be running other subroutine when 1 second elapse
 
    ; turn led on
    ldr r5, =0x000f0000
    str r5, [r1]             ; set the bit -> turn off the LED
    str r4, [r2]             ; clear the bit -> turn on the LED
    mov r4, r4, lsl #1
    ; check led bounds
    ldr r5, =led_end_bit
    cmp r4, r5
    ldreq r4, =led_start_bit ; reset led bit if eq
    add r0, #1000            ; add 1000
    b wloop_sec              ; branch always

; @subroutine2: displays F-A 9-0 on seven segment display on gpio pins p0.08 to p0.15 using lookup table (optimized for pins locs)
;               the delay here is just a loop which helps demonstrating correct restoring of cpsr, lr registers by handler 
subroutine2
    ldr r0, =IO0DIR
    ldr r1, =0x0000ff00
    str r1, [r0]
	ldr r0, =seg_lt
    ldr r2, =IO0SET
	ldr r3, =IO0CLR
    mov r4, #60    
    
wloop_seg
    ldrlt r4, =60            ; if r4 < 0 then reset r4
    str r1, [r3]             ; clear bits
    ldr r8, [r0, r4]         ; temp lookup table val
    str r8, [r2]
    bl delay
    subs r4, #4
    b wloop_seg

delay
    stmfd sp!, {r0}
    ldr r0, =1455000;0
do_delay
    subs r0, #1
    bne do_delay ; while (r0 != 0)
    ldmfd sp!, {r0}
    bx lr
 
 
 
    AREA    Stuff, DATA, READWRITE

timeval            dcd 0

seg_lt             dcd 0x3F00, 0x0600 ; lookup table for 7seg display
                   dcd 0x5B00, 0x4F00
                   dcd 0x6600, 0x6D00
                   dcd 0x7D00, 0x0700
                   dcd 0x7F00, 0x6F00
                   dcd 0x7700, 0x7C00
                   dcd 0x3900, 0x5E00
                   dcd 0x7900, 0x7100

struct_pt_start
struct_sub1        space struct_size   ; stack pointer, thread status (unused), etc.
struct_sub2        space struct_size
struct_pt_end

struct_pt          dcd struct_pt_end   ; struct_pt_end, means nothing is running

stack_sub1         space stack_size
stack_sub2         space stack_size

    end