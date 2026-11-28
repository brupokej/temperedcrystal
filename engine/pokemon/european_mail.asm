ParseMailLanguage:
	ld c, MAIL_LANG_ENGLISH
	ld hl, sPartyMon1MailNationality - sPartyMon1Mail
	add hl, de
	ld a, [hli]
	cp 'E'
	ret nz
	ld a, [hli]
	assert MAIL_LANG_ENGLISH + 1 == MAIL_LANG_FRENCH
	inc c
	cp 'F'
	ret z
	assert MAIL_LANG_FRENCH + 1 == MAIL_LANG_GERMAN
	inc c
	cp 'G'
	ret z
	assert MAIL_LANG_GERMAN + 1 == MAIL_LANG_ITALIAN
	inc c
	cp 'I'
	ret z
	assert MAIL_LANG_ITALIAN + 1 == MAIL_LANG_SPANISH
	inc c
	cp 'S'
	ret z
	ld c, MAIL_LANG_ENGLISH
	ret

; The regular font.
StandardEnglishFont:
INCBIN "gfx/font/english.1bpp"

; An extended font.
FrenchGermanFont:
INCBIN "gfx/font/french_german.1bpp"

; An even more extended font.
SpanishItalianFont:
INCBIN "gfx/font/spanish_italian.1bpp"
