STK_UNIT equ 4
Quit equ 0x71
Plus equ 0x2B
PP equ 0x70
Dup equ 0x64
AndBits equ 0x26
OrBits equ 0x7C
N equ 0x6E

%macro _print 2
	pushad
	cmp byte [in_debug], 1
	jne %%not_from_debug
	push %1
	push %2
	push dword [stderr]
	call fprintf
	add esp, STK_UNIT*3
	jmp %%_end_print
	%%not_from_debug:
	push %1
	push %2
	call printf
	add esp, STK_UNIT*2
	%%_end_print:
	popad
%endmacro

%macro debug_print 1
	cmp byte [debug_mode], 1
	jne %%end_of_debug_print
	pushad
	mov eax, %1
	mov byte [in_debug], 1
	call rec_print
	_print blank, format_msg
	mov byte [in_debug], 0
	popad
	%%end_of_debug_print:
%endmacro

%macro read 0
	pushad
	push dword [stdin]
	push 80 ; max input length 
	push buffer
	call fgets
	add esp, STK_UNIT*3
	popad
%endmacro

%macro convert_from_ascii 2
	cmp %1, 0x39
	jg %%char
	sub %1, 0x30
	jmp %2
	%%char: sub %1, 0x37	; decimal value in %1
%endmacro			

%macro new_link 0
	pushad
	push 5			; first byte for decimal number with 2 digits, the rest is a pointer to the next link
	call malloc
	add esp, STK_UNIT
	mov [temp], eax
	popad
	mov eax, [temp]
	mov dword [eax+1], 0x0
%endmacro

%macro deep_copy_list 0
	mov ecx, 0x0
	mov eax, 0x0
	mov dword [_ptr], 0x0
	%%copy_loop:
	new_link
	mov ecx, [ebx]
	mov byte [eax], cl	; copy value
	mov [edx+1], eax
	mov edx, [edx+1]
	cmp dword [_ptr], 0x0
	jne %%not_first
	mov [_ptr], edx
	%%not_first:
	mov ebx, [ebx+1]
	cmp ebx, 0x0
	jne %%copy_loop
	mov edx, [_ptr]
%endmacro

%macro push_calc_stack 1
	pushad
	debug_print %1
	mov [temp], %1
	mov eax, dword [size_of_stack]
	mov ebx, STK_UNIT 
	mul ebx
	add eax, [BasePTR]	; eax = last place is calc_stack
	cmp eax, [StackPTR]
	jne %%no_overflow
	free_list dword [temp]
	_print overflow_msg, format_msg
	popad
	mov eax, 0x0		; calc_stack is full
	jmp %%end_of_push
	%%no_overflow:
	mov edx, [temp]
	add dword [StackPTR], STK_UNIT
	mov eax, [StackPTR]
	mov [eax], edx
	popad
	%%end_of_push:
%endmacro

%macro pop_calc_stack 0
	pushad
	mov ebx, [BasePTR]
	mov eax, [StackPTR]
	cmp eax, ebx
	jg %%no_empty
	_print empty_msg, format_msg
	popad
	mov eax, 0x0		; calc_stack is empty
	jmp %%end_of_pop
	%%no_empty:
	popad
	mov eax, [StackPTR]
	mov eax, [eax]
	sub dword [StackPTR], STK_UNIT
	%%end_of_pop:
%endmacro

%macro free_list 1
	pushad
	mov eax, %1
	%%free_loop:
	mov edx, eax		; edx = currlink
	mov eax, [eax+1]	; eax = currlink->next
	;; --- free currlink ---
	pushad
	push edx
	call free
	add esp, STK_UNIT
	popad
	cmp eax, 0x0
	jne %%free_loop
	popad
%endmacro
	
section .data
	offset: dd 0
	index: dd 0x0		; buffer index - used in the insert process
	counter: dd 0x0
	debug_mode: db 0
	size_of_stack: dd 0x5
	num_of_digits: dd 0
	sign: db 0
	zero_val: dd 0
	link_before_zero_list: dd 0
	in_debug: db 0

section .bss
	buffer: resb 80
	StackPTR: resd 1
	BasePTR: resd 1
	temp: resd 1
	_ptr: resd 1
	_listToFree: resd 1
	_listToInsert: resd 1

section .rodata
	format_string: db "%s", 0
	format_number: db "%X", 0
	format_msg: db "%s", 10, 0 
	calc_string: db "calc: ", 0
	blank: db "", 0
	overflow_msg: db "Error: Operand Stack Overflow", 0
	empty_msg: db "Error: Insufficient Number of Arguments on Stack", 0

section .text
  align 16
  global main
  extern printf
  extern fprintf
  extern malloc 
  extern calloc
  extern free 
  extern fgets
  extern stdin
  extern stderr

main:
	
	;------------ read command line arguments ------------

	mov ecx, [esp+4]	 ; ecx = argc
	dec ecx

	cmp ecx, 0	; no arguments
	je init_stack

	mov edx, 1	; index in argv[] - skip argv[0]	 

	loop:
	mov ebx, [esp+8]	; pointer to argv[]
	mov ebx, [ebx+4*edx]	; get argv[] (still a pointer)
	cmp word [ebx], '-d'
	jne _else
	inc byte [debug_mode]
	jmp _last
	_else:
		mov dword [size_of_stack], 0
		mov ebx, [ebx]
		convet_size_of_stack:
			mov eax, ebx
			and eax, 0xFF		; mask
			cmp eax, 0x39
			jg _char
			sub eax, 0x30		; pure value
			jmp adding
			_char: sub eax, 0x37
			adding: add [size_of_stack], eax
			shr ebx, 8
			mov eax, ebx
			and eax, 0xFF
			cmp eax, 0
			je _last 	; size is one digit
			shl dword [size_of_stack], 4	; place to new digit
		jmp convet_size_of_stack

	_last: inc edx
	dec ecx
	jne loop

	;-----------------  init stack -----------------

	init_stack:
	push dword [size_of_stack]
	push 4
	call calloc
	add esp, STK_UNIT*2
	sub eax, 4
	mov [StackPTR], eax
	mov [BasePTR], eax

	call myCalc
	_print eax, format_number
	_print blank, format_msg
	ret

	;------------  start the RPN Calculator ------------

	myCalc:

	_print calc_string, format_string

	read

	mov dword [index], 0
	mov dword [offset], 0
	mov dword [num_of_digits], 0
	mov ecx, buffer

	; ----- remove leading zeros from input -----

	removing_zero:
	cmp dword [ecx], 0x0
	jne continute
	mov ebx, buffer
	add dword [index], 4
	add ebx, [index]
	mov ecx, ebx
	
	continute:
	mov ebx, 0xFF
	and ebx, [ecx]		; MASK
	cmp ebx, 0xA
	je zero_input
	cmp ebx, 0x30
	jne start_calculate
	cmp dword [num_of_digits], 80
	je zero_input
	shr dword [ecx], 8
	inc dword [num_of_digits]
	jmp removing_zero
	
	zero_input:
	mov ebx, 0x30
	mov dword [num_of_digits], 79
	jmp odd_after_shift

	start_calculate:
	mov edx, [index]
	add dword [offset], edx

	;--- if input value is an operation: ---

	cmp ebx, Quit
	je quit
	cmp ebx, Plus
	je addition
	cmp ebx, PP
	je pop_and_print
	cmp ebx, Dup
	je duplicate
	cmp ebx, AndBits
	je bitwise_and
	cmp ebx, OrBits
	je bitwise_or
	cmp ebx, N
	je num_of_hexa_digits

	; else (input value is a number):


	; -------- check number of digits is even \ odd --------

	mov dword [num_of_digits], 0

	check_loop:
	mov edx, buffer
	add edx, [offset]
	mov eax, 0x0
	mov al, byte [edx]
	cmp eax, 0xA
	je _length
	cmp eax, 0x0
	je not_a_digit			; was a leading zero
	inc dword [num_of_digits]
	not_a_digit:
	inc dword [offset]
	jmp check_loop

	_length:			; number + newline
	mov edx, 0x1
	and edx, [num_of_digits]
	cmp edx, 0x0
	je even
	jmp odd

	; -------- first link --------

	even: 				; read 2 first digits from buffer
	
	mov dword [num_of_digits], 0
	shr dword [ecx], 8
	
	new_link ; init first link

	mov edx, eax			; edx = first link in list

	convert_from_ascii ebx, .insert
	.insert:
	mov [edx], ebx			; put digit in the link
	mov dword [edx+1], 0x0		; first link->next = null
	inc dword [num_of_digits]
	cmp dword [ecx], 0x0
	jne continue3
	mov ebx, buffer
	add dword [index], 4
	add ebx, [index]
	mov ecx, ebx
	continue3:
	mov ebx, 0xFF
	and ebx, [ecx]			; MASK
	cmp ebx, 0xA			; end of number
	je end_of_insert
	shr dword [ecx], 8
	shl byte [edx], 4		; make place for the next digit
	convert_from_ascii ebx, .insert_sec_digit
	.insert_sec_digit: add [edx], ebx
	inc dword [num_of_digits]
	jmp insert_to_list

	odd:				; read first digit from buffer

	mov dword [num_of_digits], 0
	shr dword [ecx], 8

	odd_after_shift:

	new_link ; init first link

	mov edx, eax			; edx = first link in list

	convert_from_ascii ebx, .insert
	.insert:
	mov [edx], ebx			; put digit in the link
	mov dword [edx+1], 0x0		; first link->next = null
	inc dword [num_of_digits]
	mov ebx, 0xFF
	and ebx, [ecx]			; MASK
	cmp ebx, 0xA			; end of number
	je end_of_insert
	jmp insert_to_list

	; -------- rest links --------

	insert_to_list:
	cmp dword [num_of_digits], 80
	je end_of_insert
	cmp dword [ecx], 0x0
	jne continute1
	mov ebx, buffer
	add dword [index], 4
	add ebx, [index]
	mov ecx, ebx
	continute1:
	mov ebx, 0xFF
	and ebx, [ecx]		; MASK	
	cmp ebx, 0xA
	je end_of_insert		; end of number
	shr dword [ecx], 8

	new_link

	mov [eax+1], edx		; new link->next = prev link
	mov edx, eax			; edx = new first link in list		
	convert_from_ascii ebx, .insert
	.insert:
	mov byte [edx], bl		; put digit in the link

	inc dword [num_of_digits]
	cmp dword [num_of_digits], 80
	je end_of_insert
	cmp dword [ecx], 0x0
	jne continute2
	mov ebx, buffer
	add dword [index], 4
	add ebx, [index]
	mov ecx, ebx
	continute2:
	mov ebx, 0xFF
	and ebx, [ecx]
	cmp ebx, 0xA
	je end_of_insert
	shr dword [ecx], 8
	shl byte [edx], 4		; make place for the next digit
	convert_from_ascii ebx, .insert_sec_digit
	.insert_sec_digit: add [edx], ebx
	inc dword [num_of_digits]
	jmp insert_to_list
	
	end_of_insert:			; push list to the stack
	push_calc_stack edx

	jmp myCalc
	
	ret

; -------- calculator operations --------

quit:		
	clean_stack:
	mov eax, [BasePTR]
	cmp eax, [StackPTR]
	je end_of_clean
	pop_calc_stack

	free_list eax
	jmp clean_stack

	end_of_clean:
	mov eax, [BasePTR]
	add eax, 4
	push eax
	call free			; free calc_stack
	add esp, STK_UNIT

	mov eax, [counter]
	ret

addition:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0
	je myCalc
	mov ebx, eax
	pop_calc_stack
	cmp eax, 0x0
	jne args_ok3
	push_calc_stack ebx
	jmp myCalc
	args_ok3:
	mov dword [_listToFree], ebx 	;save for free ebx 
	mov edx, eax
	mov dword [_listToInsert], edx
	mov ecx, 0x0
	
	add_loop:
	mov cl, byte [edx] 
	adc cl, byte [ebx]
	pushfd
	mov byte [edx], cl 		; edx contain the result 
	cmp dword [ebx+1], 0x0
	je check_carry
	mov ebx, [ebx+1]
	cmp dword [edx+1], 0x0
	je first_list_is_shorter1
	mov edx, [edx+1]
	popfd
	jmp add_loop
	
	first_list_is_shorter1:
	deep_copy_list
	popfd
	jmp carry_loop
	
	check_carry:
	popfd
	jnc end_of_add
	pushfd
	cmp dword [edx+1], 0x0
	je add_new_link
	mov edx, [edx+1]
	popfd
	jnc end_of_add

	carry_loop:
	adc byte [edx], 0
	pushfd
	jc check_carry
	popfd
	jmp end_of_add	
	
	add_new_link:
	popfd				; need to clean it
	mov ecx, eax
	new_link
	mov byte [eax], 1
	mov [edx+1], eax
	mov eax, ecx
	
	end_of_add:
	free_list [_listToFree]
	mov dword eax , [_listToInsert]
	push_calc_stack eax
	jmp myCalc
	
pop_and_print:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0
	je myCalc
	mov dword [_listToFree], eax
	
	_start_print:
	call rec_print

	_newline:
	_print blank, format_msg

	free_list [_listToFree]

	jmp myCalc

rec_print:
	cmp dword [eax+1], 0x0
	je _print_last
	push eax			; original link
	mov eax, [eax+1]		; eax = original link -> next
	call rec_print
	pop eax
	do_print:
	mov ecx, 0x0
	mov cl, byte [eax]
	mov edx, 0xF0
	and edx, ecx
	cmp edx, 0
	jne regular_print


	_print edx, format_number 	 ; print zero

	regular_print:
	_print ecx, format_number
	ret

	_print_last:			; no need to check leading zero
	mov ecx, 0x0
	mov cl, byte [eax]
	_print ecx, format_number
	ret
	 
duplicate:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0
	je myCalc
	
	push_calc_stack eax

	mov ecx, eax
	mov byte [sign], 0

	dup_loop:
	new_link
	mov edx, [ecx]
	mov byte [eax], dl
	cmp byte [sign], 0
	jne not_first
	mov [_listToInsert], eax
	mov ebx, eax
	inc byte [sign]
	jmp after_assign
	not_first:
	mov [ebx+1], eax
	mov ebx, [ebx+1]
	after_assign:
	cmp dword [ecx+1], 0x0
	je end_of_dup
	mov ecx, [ecx+1]
	jmp dup_loop

	end_of_dup:
	mov dword eax, [_listToInsert]
	push_calc_stack eax

	jmp myCalc
	
bitwise_and:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0
	je myCalc
	mov ebx, eax
	pop_calc_stack
	cmp eax, 0x0
	jne args_ok1
	push_calc_stack ebx
	jmp myCalc
	args_ok1:
	mov [_listToFree], ebx
	mov edx, eax
	mov [_listToInsert], eax
	mov ecx, 0x0
	mov dword [zero_val], 0x0

	and_loop:
	mov cl, byte [edx] 
	and cl, byte [ebx]
	mov byte [edx], cl 		; edx contain the result 
	cmp dword [ebx+1], 0x0
	je one_list_is_shorter
	mov ebx, [ebx+1]
	cmp dword [edx+1], 0x0
	je one_list_is_shorter
	mov edx, [edx+1]
	jmp and_loop

	one_list_is_shorter:
	cmp dword [edx+1], 0x0
	je removing_leading_zeros
	free_list [edx+1]
	mov dword [edx+1], 0x0

	removing_leading_zeros:
	mov eax, [_listToInsert]
	mov ebx, eax
	mov eax, [eax+1]
	cmp eax, 0x0
	je end_of_and

	zero_loop:
	cmp byte [eax], 0x0
	jne not_zero_val
	cmp dword [zero_val], 0x0
	jne no_update
	
	mov [zero_val], eax
	mov [link_before_zero_list], ebx
	jmp before
	
	not_zero_val:
	mov dword [zero_val], 0x0
	no_update:
	mov ebx, eax

	before:
	mov eax, [eax+1]
	cmp eax, 0x0
	jne zero_loop

	cmp dword [zero_val], 0x0
	je end_of_and
	free_list [zero_val]
	mov eax, [link_before_zero_list]
	mov dword [eax+1], 0x0

	end_of_and:
	mov eax, [_listToInsert]
	push_calc_stack eax
	free_list [_listToFree]
	jmp myCalc

bitwise_or:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0
	je myCalc
	mov ebx, eax
	pop_calc_stack
	cmp eax, 0x0
	jne args_ok2
	push_calc_stack ebx
	jmp myCalc
	args_ok2:
	mov [_listToFree], ebx 		;save for free ebx 
	mov edx, eax
	mov [_listToInsert], edx

	or_loop:
	mov cl, byte [edx]
	or cl, byte [ebx]
	mov byte [edx], cl 		; edx contain the result 
	cmp dword [ebx+1], 0x0
	je end_of_or
	mov ebx, [ebx+1]
	cmp dword [edx+1], 0x0
	je first_list_is_shorter
	mov edx, [edx+1]
	jmp or_loop

	first_list_is_shorter:
	deep_copy_list

	end_of_or:
	free_list [_listToFree]
	mov dword eax, [_listToInsert]
	push_calc_stack eax
	jmp myCalc 

num_of_hexa_digits:
	inc dword [counter]
	pop_calc_stack
	cmp eax, 0x0			; eax = first link is list
	je myCalc			; stack is empty
	mov [_listToFree], eax
	mov ecx, 0x0			; num of hexa digits
	
	count_loop:
	cmp dword [eax+1], 0x0		; currlink->next == null
	je _last_link
	add ecx, 2
	mov eax, [eax+1]		; eax = currlink->next
	jmp count_loop

	_last_link:
	mov ebx, 0xF0			; mask the first digit
	and ebx, [eax]
	cmp ebx, 0x0			; link value is one digit number
	je one_digit
	inc ecx
	one_digit: inc ecx
	
	end_of_counting:
	new_link
	mov [eax], ecx
	mov dword [eax+1], 0x0
	push_calc_stack eax
	free_list [_listToFree]
	jmp myCalc

