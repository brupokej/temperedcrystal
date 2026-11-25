OpenSRAM::
; if invalid bank, sram is disabled
	cp NUM_SRAM_BANKS
	jr c, .valid
if DEF(_DEBUG)
	push af
	push bc
	ld b, 1
.loop
	sla b
	dec a
	jr nz, .loop
	ld a, BANK(sOpenedInvalidSRAM)
	call OpenSRAM
	ld a, [sOpenedInvalidSRAM]
	or b
	ld [sOpenedInvalidSRAM], a
	pop bc
	pop af
endc
	jr CloseSRAM

.valid:
; switch to sram bank a
	push af
if !DEF(TEMPERED_NO_RTC)
; latch clock data
	ld a, 1
	ld [rRTCLATCH], a
endc
; enable sram/clock write
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
; select sram bank
	pop af
	ld [rRAMB], a
	ret

CloseSRAM::
	push af
	ld a, RAMG_SRAM_DISABLE
if !DEF(TEMPERED_NO_RTC)
; reset clock latch for next time
	ld [rRTCLATCH], a
endc
; disable sram/clock write
	ld [rRAMG], a
	pop af
	ret
