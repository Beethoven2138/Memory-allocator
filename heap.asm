;AUTHOR: SAXON SUPPLE
;LICENSE: GPL v3
;USERSPACE MEMORY ALLOCATOR USING BUDY ALLOCATION ALGORITHM

;RDI, RSI, RDX, RCX

STRUC list_head
	.next: RESQ 1
	.prev: RESQ 1
	.size:
ENDSTRUC

;Describes a free block of memory. Linked list. container_of() == list-1
STRUC block
	.addr: RESQ 1
	.list: RESQ 2
	.size: RESQ 1
ENDSTRUC

;Describes a memory block size.
STRUC block_list
	.head: RESQ 1
	.tail: RESQ 1
	.size: RESQ 1
ENDSTRUC

section .text
	global init_heap
	global free_heap
	global inc_heap
	global malloc
	global calloc
	global realloc
	global free
	global _memmove
	global _memcpy

	global alloc_block
	global free_block

	global _round_size
	global _log2
	global _find_normal

BLOCK_TYPES:	EQU 15		;2^0 - 2^14
BLOCK_SIZE:	EQU 32		;in bytes
BLOCK_LIST_SIZE:	EQU 24

section .bss
	block_region_addr RESQ 0x3800
	heap_start RESQ 2048


section .data
	block_lists DQ 0,0,1,0,0,2,0,0,4,0,0,8,0,0,16,0,0,32,0,0,64,0,0,128,0,0,256,0,0,512,0,0,1024,0,0,2048,0,0,4096,0,0,8192,0,0,16384
	block_region_size DQ 0x1000	;number of blocks it can hold
	block_count DQ 0
	heap_size DQ 16384

;block* alloc_block(void);returns address of block
alloc_block:
	MOV RAX, [block_count]
	CMP RAX, [block_region_size]
	JGE _exit_fail
	ADD QWORD [block_count], 1
	MOV RCX, BLOCK_SIZE
	MUL RCX
	ADD RAX, block_region_addr
	RET
_exit_fail:
	XOR RAX, RAX
	RET

;void free_block(block *addr)
free_block:
	MOV RCX, RDI
	SUB RCX, block_region_addr
	MOV RAX, RCX
	MOV R15, BLOCK_SIZE
	DIV R15
	DEC RAX
	CMP RAX, [block_count]
	JE _normal
	MOV RCX, [block_count]
	SUB RCX, RAX
	MOV RAX, BLOCK_SIZE
	MUL RCX
	MOV RDX, RAX
	MOV RSI, RDI
	ADD RSI, RDX
	CALL _memmove
_normal:
	SUB QWORD [block_count], 1
	XOR RAX, RAX
	RET

;void *_find_free_block(int size_log2);
_find_free_block:
	MOV RCX, BLOCK_LIST_SIZE
	MOV RAX, RDI
	MUL RCX
	MOV RCX, RAX
	ADD RCX, block_lists
	CMP QWORD [RCX + block_list.head], 0
	JNE _find_normal
	INC RDI
	PUSH RCX
	CALL _find_free_block
	ADD RAX, 8
	MOV RDI, RAX
	CALL list_del
	MOV RDX, [RDI + block.size]
	SHR RDX, 1
	MOV [RDI + block.size], RDX
	CALL alloc_block
	MOV [RAX + block.size], RDX
	MOV R14, [RDI + block.addr]
	ADD RDX, R14
	MOV [RAX + block.addr], RDX
	POP RCX
	PUSH RDI
	MOV RSI, [RCX + block_list.head]
	MOV RDI, RAX
	CALL list_add
	POP RDI
	CALL list_add
	SUB RDI, 8
	MOV RAX, RDI
	RET
_find_normal:
	MOV RAX, [RCX + block_list.head]
	MOV RDX, [RAX + list_head.next]
	MOV [RCX + block_list.head], RDX
	SUB RAX, 8
	RET

;void *malloc(unsigned int size);
malloc:
	CALL _round_size
	MOV RDI, RAX
	CALL _log2
	MOV RDI, RAX
	CALL _find_free_block
	MOV RCX, RAX
	MOV RAX, [RCX + block.addr]
	RET

;void *calloc(size_t nmemb, size_t size);
calloc:
	CMP RDI, 0
	JE _calloc_exit_fail
	CMP RSI, 0
	JE _calloc_exit_fail
	MOV RAX, RSI
	MUL RDI
	MOV RDI, RAX
	CALL malloc
	JMP _calloc_exit
_calloc_exit_fail:
	XOR RAX, RAX
_calloc_exit:
	RET

;void *realloc(void *ptr, size_t size);
realloc:
	CMP RDI, 0
	JE _case1
	CMP RSI, 0
	JE _case2
	MOV RCX, 1
	MOV RBX, block_region_addr
_realloc_loop:
	CMP RCX, [block_count]
	JG _realloc_exit
	CMP [RBX + block.addr], RDI
	JE _realloc_found
	ADD RBX, BLOCK_SIZE
	INC RCX
	JMP _realloc_loop
_realloc_found:
	SUB RSP, [RBX + block.size]
	MOV RSI, RDI
	MOV RDI, RSP
	MOV RDX, [RBX + block.size]
	CALL _memcpy
	MOV RDI, [RBX + block.addr]
	CALL free
	MOV RDI, [RBX + block.size]
	CALL malloc
	MOV R12, RAX
	MOV RDI, RAX
	MOV RSI, RSP
	MOV RDX, [RBX + block.size]
	CALL _memcpy
	MOV RAX, R12
	JMP _realloc_exit
_case1:
	MOV RDI, RSI
	CALL malloc
	JMP _realloc_exit
_case2:
	CALL free
_realloc_exit:
	RET

free:
	MOV RDX, block_region_addr
	MOV RCX, 1
_free_loop:
	CMP RCX, [block_count]
	JG _free_exit
	CMP [RDX + block.addr], RDI
	JE _found
	ADD RDX, BLOCK_SIZE
	INC RCX
	JMP _free_loop
_found:
	MOV RDI, [RDX + block.size]
	CALL _log2
	MOV RDI, block_lists
	MOV R13, BLOCK_LIST_SIZE
	MUL R13
	ADD RDI, RAX
	MOV RSI, [RDI + block_list.head]
	LEA RDI, [RDX + block.list]
	CALL list_add
_free_exit:
	XOR RAX, RAX
	RET

;int init_heap(void)
;returns -1 on failure, size of heap on success
;start with one block of size 2^14. Reserve region for allocating more blocks
init_heap:
	RET
	LEA RDI, [block_lists + 360 - BLOCK_LIST_SIZE]
	MOV QWORD [RDI + block_list.size], 16384
	RET
	CALL alloc_block
	RET
	CMP RAX, 0
	JE _INIT_HEAP_EXIT
	MOV QWORD [RDI + block_list.head], RAX
	MOV QWORD [RDI + block_list.tail], RAX
	MOV QWORD [RAX + block.size], 16384
	MOV RCX, [heap_start]
	MOV QWORD [RAX + block.addr], RCX
	MOV QWORD [RAX + block.list], 0
	MOV QWORD [RAX + block.list + 8], 0
_INIT_HEAP_EXIT:
	RET

free_heap:
	MOV RAX, 12
	XOR RDI, RDI
	SYSCALL
	RET

;int inc_heap(unsigned int amount);
inc_heap:
	;; sys_brk
	ADD RDI, [heap_start]
	ADD RDI, [heap_size]
	MOV RAX, 12
	SYSCALL
	CMP RAX, 0
	JL _INC_HEAP_EXIT
	MOV [heap_size], RDI
_INC_HEAP_EXIT:
	RET

;void *memmove(void *dest, const void *src, size_t n);
;RDI = dest, RSI = src, RDX = n
_memmove:
	SUB RSP, RDX
	MOV RCX, RDX
_loop1:
	CMP RCX, 0
	JE _finish1
	MOV RAX, [RSI + RCX - 1]
	MOV [RSP + RCX - 1], AL
	DEC RCX
	JMP _loop1
_finish1:
	MOV RCX, RDX
_loop2:
	CMP RCX, 0
	JE _finish2
	MOV RAX, [RSP + RCX - 1]
	MOV [RDI + RCX - 1], AL
	DEC RCX
	JMP _loop2
_finish2:
	ADD RSP, RDX
	MOV RAX, RDI
	RET

;void *memcpy(void *dest, const void *src, size_t n);
;RDI = dest, RSI = src, RDX = n
_memcpy:
	DEC RDX
	CMP RDX, 0
	JLE _cpy_end
	MOV RAX, [RSI + RDX]
	MOV [RDI + RDX], AL
	JMP _memcpy
_cpy_end:
	MOV RAX, RDI
	RET

_clear_block:
	XOR RAX, RAX
	MOV QWORD [RDI + block.addr], RAX
	MOV QWORD [RDI + block.list], RAX
	MOV QWORD [RDI + block.list + 8], RAX
	MOV QWORD [RDI + block.size], RAX
	RET

;int _round_size(int size)
_round_size:
	;; EPIC BIT TWIDDLING HACK!!!
	DEC RDI
	MOV RAX, RDI
	SHR RDI, 1
	OR RAX, RDI
	MOV RDI, RAX
	SHR RDI, 1
	OR RAX, RDI
	MOV RDI, RAX
	SHR RDI, 2
	OR RAX, RDI
	MOV RDI, RAX
	SHR RDI, 4
	OR RAX, RDI
	MOV RDI, RAX
	SHR RDI, 8
	OR RAX, RDI
	MOV RDI, RAX
	SHR RDI, 16
	OR RAX, RDI
	MOV RDI, RAX
	INC RAX
	RET

;int _log2(int number);
_log2:
	XOR RAX, RAX
_log2_loop:
	CMP RDI, 0
	JE _log2_end
	SHR RDI, 1
	INC RAX
	JMP _log2_loop
_log2_end:
	DEC RAX
	RET



;CODE FOR THE LINKED LISTS!!!

;void init_list(struct *list_head)
init_list:
	MOV QWORD [RDI + list_head.next], 0
	MOV QWORD [RDI + list_head.prev], 0
	RET

;void list_add(struct list_head *new, struct list_head *head)
;RDI: new, RSI: head
list_add:
	MOV RAX, [RSI + list_head.next] ;list_head *RAX = head->next
	MOV [RDI + list_head.next], RAX ;new->next = head->next
	MOV [RDI + list_head.prev], RSI ;new->prev = head
	CMP RAX, 0
	JE _skip
	MOV [RAX + list_head.prev], RDI ;head->next->prev = new
_skip:
	CMP RSI, 0
	JE _skip2
	MOV [RSI + list_head.next], RDI
_skip2:
	RET

;void list_del(struct list_head *entry)
;RDI: entry
list_del:
	MOV RAX, [RDI + list_head.prev]
	MOV RCX, [RDI + list_head.next]
	CMP RCX, 0
	JE _next
	MOV [RCX + list_head.prev], RAX
_next:
	CMP RAX, 0
	JE _exit
	MOV [RAX + list_head.next], RCX
_exit:
	RET
