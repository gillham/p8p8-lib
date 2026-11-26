; File I/O routines for the Apple II with DOS 3.3 (the appleii target of p8p8), through
; DOS's file manager, and RWTS for the catalog.  The program is one that DOS started
; (BRUN): DOS must be in memory.
;
; A file's name is DOS's: up to 30 characters, the first a letter, no comma.  Small
; letters are made capitals.  The drive is drivenumber (1 or 2; 0, as it is at first,
; is the drive that DOS used last, which is where the program came from), the slot is
; that of DOS's last access.
;
; DOS 3.3 does not keep the length of a file, only its sectors.  So what a file is
; decides how it is written and read:
; - file_type = BINARY (as it is at first): a B file, with the four bytes that BSAVE
;   writes before the data, an address and the length.  f_write counts the length and
;   f_close_w writes it; f_read ends where it says.  Every byte comes back as written.
; - file_type = TEXT: a T file as Applesoft and DOS's commands write and read them:
;   every character with its bit 7 set, a line ends with a carriage return ('\n'
;   here), and the file ends at the first 0 byte.  f_write sets bit 7 of what it
;   writes; f_read clears it and stops at the 0.
; f_open() looks at the type that the catalog has for the file; a file of another type
; (Applesoft's and the others) is read as it is, up to the end of its last sector.
;
; One file can be open for reading and one for writing at a time.  The calls that take
; only a name (delete, rename) borrow the memory of the file that is not open: with
; both open, they fail.
; Not there: a position in a file (f_seek, f_tell).
;
; NOTE: f_readline() returns a status in place of a carry flag.

%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    const ubyte TEXT = 0
    const ubyte BINARY = 4

    ; the file manager's calls
    const ubyte FM_OPEN = 1
    const ubyte FM_CLOSE = 2
    const ubyte FM_READ = 3
    const ubyte FM_WRITE = 4
    const ubyte FM_DELETE = 5
    const ubyte FM_RENAME = 9
    const ubyte RANGE = 2               ; of bytes, where the file is
    const ubyte RANGE_AT = 4            ; of bytes, at a position
    ; its errors
    const ubyte ERR_END_OF_DATA = 5
    const ubyte ERR_NOT_FOUND = 6
    const ubyte ERR_IO = 8

    ubyte drivenumber = 0           ; 1 or 2; 0: the drive that DOS used last
    ubyte slot = 0                  ; 1 to 7; 0: the slot that DOS used last
    ubyte file_type = BINARY        ; what f_open_w makes: BINARY or TEXT
    bool internal_ok = true         ; whether the last disk operation succeeded, for status() and status_code()
    ubyte dos_error = 0             ; DOS's code of the last operation that failed

    ; what the file manager wants for an open file: its 45 bytes, a sector for the
    ; list of the file's sectors, a sector of data
    const uword FILE_MEMORY = 45 + 256 + 256
    uword read_memory = memory("p8_diskio_read", FILE_MEMORY, 0)
    uword write_memory = memory("p8_diskio_write", FILE_MEMORY, 0)
    uword sector = memory("p8_diskio_sector", 256, 0)       ; of the catalog

    bool read_open = false
    bool read_ended = false
    ubyte read_type
    uword read_left                 ; BINARY: how many of its bytes are not read yet
    bool write_open = false
    ubyte write_type
    uword write_count               ; BINARY: how many bytes were written
    uword write_address = 0         ; BINARY: the address that the file gets (save)

    ; what was read ahead of the file that is open for reading
    const ubyte AHEAD = 64
    ubyte[AHEAD] read_ahead
    ubyte read_pos = 0
    ubyte read_len = 0

    ubyte[30] dos_name              ; a name as DOS has it: capitals with bit 7 set, spaces after it
    ubyte[30] dos_name2
    ubyte[128] high                 ; text on its way to the disk
    uword fm                        ; the file manager's parameters
    ubyte[4] header                 ; of a B file: its address and its length

    ; ----- DOS's calls -----

    asmsub fm_parameters() -> uword @AY {
        %asm {{
            jsr  $03dc              ; (Y and A: low and high byte of the address)
            tax
            tya
            pha
            txa
            tay
            pla
            rts
        }}
    }

    asmsub rwts_parameters() -> uword @AY {
        %asm {{
            jsr  $03e3              ; (Y and A: low and high byte of the address)
            tax
            tya
            pha
            txa
            tay
            pla
            rts
        }}
    }

    asmsub fm_call(ubyte create @X) -> ubyte @A {
        ; -- the file manager with what is in its parameters (X = 0: OPEN may make the file);
        ;    returns 0 or its error
        %asm {{
            jsr  $03d6
            jsr  $03dc
            sty  P8ZP_SCRATCH_W1
            sta  P8ZP_SCRATCH_W1+1
            ldy  #$0a
            lda  (P8ZP_SCRATCH_W1),y
            rts
        }}
    }

    asmsub rwts_read(ubyte track @A, ubyte sect @Y) -> bool @Pc {
        ; -- a sector of the disk into the sector buffer; the carry says that it failed
        %asm {{
            pha
            tya
            pha
            jsr  $03e3              ; (Y and A: low and high byte of RWTS's parameters)
            sty  P8ZP_SCRATCH_W1
            sta  P8ZP_SCRATCH_W1+1
            ldy  #5
            pla
            sta  (P8ZP_SCRATCH_W1),y        ; sector
            dey
            pla
            sta  (P8ZP_SCRATCH_W1),y        ; track
            dey
            lda  #0
            sta  (P8ZP_SCRATCH_W1),y        ; any volume
            lda  diskio.drivenumber
            beq  +
            dey
            sta  (P8ZP_SCRATCH_W1),y        ; drive
+           lda  diskio.slot
            beq  +
            asl  a
            asl  a
            asl  a
            asl  a
            ldy  #1
            sta  (P8ZP_SCRATCH_W1),y        ; slot * 16
+           ldy  #8
            lda  diskio.sector
            sta  (P8ZP_SCRATCH_W1),y
            iny
            lda  diskio.sector+1
            sta  (P8ZP_SCRATCH_W1),y
            ldy  #12
            lda  #1
            sta  (P8ZP_SCRATCH_W1),y        ; read
            ldy  P8ZP_SCRATCH_W1
            lda  P8ZP_SCRATCH_W1+1
            jsr  $03d9
            lda  #0
            sta  $48                ; (as the monitor wants it after RWTS)
            rts
        }}
    }

    asmsub text_from_disk(uword buffer @R0, uword count @AY) -> uword @AY {
        ; -- text that was read: bit 7 of every byte cleared, up to a 0 byte; returns how many bytes that is
        %asm {{
            sta  P8ZP_SCRATCH_W1
            sty  P8ZP_SCRATCH_W1+1
            lda  cx16.r0L
            sta  P8ZP_SCRATCH_W2
            lda  cx16.r0H
            sta  P8ZP_SCRATCH_W2+1
            ldy  #0
            sty  cx16.r1L
            sty  cx16.r1H
_next       lda  cx16.r1L
            cmp  P8ZP_SCRATCH_W1
            bne  +
            lda  cx16.r1H
            cmp  P8ZP_SCRATCH_W1+1
            beq  _done
+           lda  (P8ZP_SCRATCH_W2),y
            beq  _done
            and  #$7f
            sta  (P8ZP_SCRATCH_W2),y
            inc  P8ZP_SCRATCH_W2
            bne  +
            inc  P8ZP_SCRATCH_W2+1
+           inc  cx16.r1L
            bne  _next
            inc  cx16.r1H
            bne  _next
_done       lda  cx16.r1L
            ldy  cx16.r1H
            rts
        }}
    }

    sub failed(ubyte code) {
        internal_ok = false
        dos_error = code
    }

    sub where() {
        ; -- the drive and the slot, when the program did not say: those of DOS's last access
        if drivenumber == 0 or slot == 0 {
            uword iob = rwts_parameters()
            if drivenumber == 0
                drivenumber = iob[2]
            if slot == 0
                slot = iob[1] >> 4
        }
    }

    sub capital(ubyte char) -> ubyte {
        if char >= 'a' and char <= 'z'
            return char - 32
        return char
    }

    sub name_for_dos(str name, uword target) {
        ubyte k = 0
        while k < 30 and name[k] != 0 {
            target[k] = capital(name[k]) | $80
            k++
        }
        while k < 30 {
            target[k] = $a0
            k++
        }
    }

    sub prepare(ubyte opcode, uword file_memory) {
        ; -- the file manager's parameters for a call on a file
        where()
        fm = fm_parameters()
        fm[0] = opcode
        fm[1] = RANGE
        pokew(fm + 2, 0)
        pokew(fm + 4, 0)
        pokew(fm + 12, file_memory)
        pokew(fm + 14, file_memory + 45)
        pokew(fm + 16, file_memory + 45 + 256)
    }

    sub prepare_name(ubyte opcode, uword file_memory) {
        ; -- for a call that takes the name in dos_name
        prepare(opcode, file_memory)
        fm[4] = 0                   ; any volume
        fm[5] = drivenumber
        fm[6] = slot
        pokew(fm + 8, &dos_name)
    }

    sub spare_memory() -> uword {
        ; -- memory for a call that takes only a name, or 0
        if not write_open
            return write_memory
        if not read_open
            return read_memory
        failed(ERR_IO)
        return 0
    }

    ; ----- the catalog -----

    ; the names of the disk, one at a time: lf_start_list(), then lf_next_entry() for as long as it is true,
    ; each time with the entry in list_filename, list_filetype (DOS's letter: T, I, A, B, S, R),
    ; list_locked and list_blocks (its size in sectors), then lf_end_list().
    ; (exists() and f_open() look through the catalog too: not between these calls.)
    str list_filename = "?" * 30
    str list_filetype = "?"
    uword list_blocks = 0
    bool list_locked = false
    ubyte list_type = 0             ; the file manager's number for the type
    str list_pattern = "?" * 30
    bool list_more = false
    ubyte list_entry = 0
    str type_letters = "IABSRabc"

    sub lf_start_list(str pattern_ptr) -> bool {
        ; -- start a list of the names that fit the pattern ("*.TXT", with * and ?); 0 or an empty pattern is all of them.
        list_pattern[0] = 0
        if pattern_ptr != 0 {
            ubyte k = 0
            while k < 30 and pattern_ptr[k] != 0 {
                list_pattern[k] = capital(pattern_ptr[k])
                k++
            }
            list_pattern[k] = 0
        }
        where()
        list_more = false
        ; (track 17, sector 0 says where the catalog begins)
        if rwts_read(17, 0) {
            failed(ERR_IO)
            return false
        }
        if rwts_read(sector[1], sector[2]) {
            failed(ERR_IO)
            return false
        }
        list_more = true
        list_entry = 0
        internal_ok = true
        return true
    }

    sub lf_next_entry() -> bool {
        ; -- the next entry, or false when there are no more.
        while list_more {
            if list_entry == 7 {
                ; (the next sector of the catalog)
                if sector[1] == 0 or rwts_read(sector[1], sector[2]) {
                    list_more = false
                    return false
                }
                list_entry = 0
            }
            uword entry = sector + 11 + (list_entry as uword) * 35
            list_entry++
            if entry[0] == 0 {
                ; (never used: nothing comes after it)
                list_more = false
                return false
            }
            if entry[0] != $ff {
                ubyte length = 30
                while length != 0 and entry[2 + length] == $a0
                    length--
                ubyte k
                for k in 0 to 29
                    list_filename[k] = entry[3 + k] & $7f
                list_filename[length] = 0
                list_locked = entry[2] & $80 != 0
                list_type = entry[2] & $7f
                list_filetype[0] = 'T'
                ubyte bits = list_type
                k = 0
                while bits != 0 {
                    list_filetype[0] = type_letters[k]
                    bits >>= 1
                    k++
                }
                list_blocks = peekw(entry + 33)
                if list_pattern[0] == 0 or strings.pattern_match(list_filename, list_pattern)
                    return true
            }
        }
        return false
    }

    sub lf_end_list() {
        list_more = false
    }

    sub list_filenames(str pattern_ptr, uword filenames_buffer, uword filenames_buf_size) -> ubyte {
        ; -- fill the buffer with the names that fit the pattern, each with a 0 after it and one more 0 after the last.
        ;    Returns how many names there are (at most 255), fewer when the buffer is full.
        ubyte files_found = 0
        uword left = filenames_buf_size
        void lf_start_list(pattern_ptr)
        while files_found != 255 and lf_next_entry() {
            ubyte length = strings.length(list_filename)
            if left < length + 2
                break
            void strings.copy(list_filename, filenames_buffer)
            filenames_buffer += length + 1
            left -= length + 1
            files_found++
        }
        lf_end_list()
        @(filenames_buffer) = 0
        return files_found
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists, otherwise false; list_type is its type then
        bool was_ok = internal_ok
        ubyte was_error = dos_error
        bool found = false
        if lf_start_list(filename)
            found = lf_next_entry()
        lf_end_list()
        internal_ok = was_ok
        dos_error = was_error
        return found
    }

    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        if not exists(filenameptr) {
            failed(ERR_NOT_FOUND)
            return false
        }
        read_type = list_type
        name_for_dos(filenameptr, &dos_name)
        prepare_name(FM_OPEN, read_memory)
        fm[2] = 1
        fm[7] = read_type
        ubyte code = fm_call(1)
        if code != 0 {
            failed(code)
            return false
        }
        read_open = true
        read_ended = false
        internal_ok = true
        if read_type == BINARY {
            ; (the address and the length that BSAVE writes)
            read_left = 4
            if read_bytes(&header, 4) != 4 {
                f_close()
                failed(ERR_END_OF_DATA)
                return false
            }
            read_left = peekw(&header + 2)
            read_ended = read_left == 0
        }
        return true
    }

    sub read_bytes(uword bufferpointer, uword num_bytes) -> uword {
        ; -- bytes of the file as they are for the program, straight from the disk
        if read_ended
            return 0
        if read_type == BINARY and num_bytes > read_left
            num_bytes = read_left
        if num_bytes == 0
            return 0
        prepare(FM_READ, read_memory)
        pokew(fm + 6, num_bytes)
        pokew(fm + 8, bufferpointer)
        ubyte code = fm_call(1)
        uword done = num_bytes
        if code != 0 {
            ; (the file manager counts down before each byte: the one it did not get is counted)
            done = num_bytes - peekw(fm + 6) - 1
            read_ended = true
            if code != ERR_END_OF_DATA
                failed(code)
        }
        when read_type {
            BINARY -> {
                read_left -= done
                if read_left == 0
                    read_ended = true
            }
            TEXT -> {
                uword text = text_from_disk(bufferpointer, done)
                if text != done {
                    done = text
                    read_ended = true
                }
            }
            else -> {
            }
        }
        return done
    }

    sub next_byte() -> uword {
        ; -- the next byte of the file that is read, or $ffff at its end
        if read_pos == read_len {
            if not read_open
                return $ffff
            read_len = lsb(read_bytes(&read_ahead, AHEAD))
            read_pos = 0
            if read_len == 0
                return $ffff
        }
        read_pos++
        return read_ahead[read_pos - 1]
    }

    sub f_read(uword bufferpointer, uword num_bytes) -> uword {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        uword actual = 0
        if not read_open
            return 0
        ; (what was read ahead first, then the rest straight into the buffer)
        while read_pos != read_len and actual != num_bytes {
            @(bufferpointer) = read_ahead[read_pos]
            read_pos++
            bufferpointer++
            actual++
        }
        if actual != num_bytes
            actual += read_bytes(bufferpointer, num_bytes - actual)
        return actual
    }

    sub f_read_all(uword bufferpointer) -> uword {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        uword total = 0
        repeat {
            uword part = f_read(bufferpointer, 8192)
            total += part
            bufferpointer += part
            if part != 8192
                return total
        }
    }

    sub f_readline(uword bufptr) -> ubyte, ubyte {
        ; Routine to read text lines from a text file.
        ; Reads characters from the input file UNTIL a return character, or 0 byte, or the end of the file.
        ; The line read will be 0-terminated in the buffer (and not contain the end of line character).
        ; A line longer than 255 characters continues in the next call, so the buffer needs room for 256 bytes.
        ; Returns the length of the line (an empty line is okay and is length 0!), and a status byte:
        ; 0 when the line ended, $40 when the file ended instead, or there was an error, or no file was open.
        ubyte size = 0
        repeat {
            uword data = next_byte()
            if data == $ffff {
                @(bufptr) = 0
                return size, $40
            }
            ubyte char = lsb(data)
            if char == '\n' or char == 0 {
                @(bufptr) = 0
                return size, 0
            }
            @(bufptr) = char
            bufptr++
            size++
            if size == 255 {
                @(bufptr) = 0
                return size, 0
            }
        }
    }

    sub f_close() {
        ; -- end an iterative file loading session (close the file).
        if read_open {
            prepare(FM_CLOSE, read_memory)
            void fm_call(1)
            read_open = false
        }
        read_pos = 0
        read_len = 0
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write, of the type that file_type says.
        ;    An existing file is overwritten.  Returns true if the file is successfully opened.
        f_close_w()
        ubyte code
        if exists(filenameptr) {
            ; (DOS would write over its beginning and leave the rest)
            name_for_dos(filenameptr, &dos_name)
            prepare_name(FM_DELETE, write_memory)
            code = fm_call(1)
            if code != 0 {
                failed(code)
                return false
            }
        }
        name_for_dos(filenameptr, &dos_name)
        prepare_name(FM_OPEN, write_memory)
        fm[2] = 1
        fm[7] = file_type
        code = fm_call(0)
        if code == ERR_NOT_FOUND {
            ; (which is what the file manager says of a file that it has just made: now it is there)
            prepare_name(FM_OPEN, write_memory)
            fm[2] = 1
            fm[7] = file_type
            code = fm_call(1)
        }
        if code != 0 {
            failed(code)
            return false
        }
        write_open = true
        write_type = file_type
        write_count = 0
        internal_ok = true
        if write_type == BINARY {
            ; (room for the address and the length: f_close_w writes them)
            pokew(&header, write_address)
            pokew(&header + 2, 0)
            return write_bytes(&header, 4, RANGE)
        }
        return true
    }

    sub write_bytes(uword bufferpointer, uword num_bytes, ubyte how) -> bool {
        prepare(FM_WRITE, write_memory)
        fm[1] = how
        pokew(fm + 6, num_bytes - 1)        ; (the file manager writes one byte more than this)
        pokew(fm + 8, bufferpointer)
        ubyte code = fm_call(1)
        if code != 0 {
            failed(code)
            return false
        }
        return true
    }

    sub f_write(uword bufferpointer, uword num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        ;    Returns true if all of them were written.
        if not write_open
            return false
        if num_bytes == 0
            return true
        if write_type != TEXT {
            write_count += num_bytes
            return write_bytes(bufferpointer, num_bytes, RANGE)
        }
        while num_bytes != 0 {
            ubyte part = len(high)
            if num_bytes < part
                part = lsb(num_bytes)
            ubyte k
            for k in 0 to part - 1
                high[k] = bufferpointer[k] | $80
            if not write_bytes(&high, part, RANGE)
                return false
            bufferpointer += part
            num_bytes -= part
        }
        return true
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        ubyte code
        if write_open {
            if write_type == BINARY {
                ; (the length, after the two bytes of the address)
                prepare(FM_WRITE, write_memory)
                fm[1] = RANGE_AT
                pokew(fm + 2, 2)        ; (a record is a byte: its number is the position)
                pokew(fm + 6, 1)        ; (two bytes: it writes one more than this)
                pokew(fm + 8, &write_count)
                code = fm_call(1)
                if code != 0
                    failed(code)
            }
            prepare(FM_CLOSE, write_memory)
            code = fm_call(1)
            if code != 0
                failed(code)
            write_open = false
        }
    }

    ; ----- status -----

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        ; -- 0, or DOS's code of the error (4 write protected, 5 end of data, 6 file not found,
        ;    8 I/O error, 9 disk full, 10 file locked)
        if internal_ok
            return 0
        return dos_error
    }

    ; ----- whole files -----

    sub save(str filenameptr, uword start_address, uword savesize) -> bool {
        ; -- save the memory block in a B file with its address, as BSAVE does: BLOAD puts it back.
        ;    An existing file is overwritten. Returns true if successful.
        ubyte was_type = file_type
        file_type = BINARY
        write_address = start_address
        bool opened = f_open_w(filenameptr)
        write_address = 0
        file_type = was_type
        if not opened
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; like save(), with no address in the file.
    sub save_raw(str filenameptr, uword start_address, uword savesize) -> bool {
        ubyte was_type = file_type
        file_type = BINARY
        bool opened = f_open_w(filenameptr)
        file_type = was_type
        if not opened
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory: at the address given, or with 0 at the address that a B file has.
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    sub load(str filenameptr, uword address_override) -> uword {
        if address_override == 0 {
            address_override = get_loadaddress(filenameptr)
            if address_override == 0
                return 0
        }
        return load_raw(filenameptr, address_override)
    }

    ; Load the given file in memory at the address given: the data of a B file, the text of a T file.
    sub load_raw(str filenameptr, uword start_address) -> uword {
        if not f_open(filenameptr)
            return 0
        uword size = f_read_all(start_address)
        f_close()
        return start_address + size
    }

    sub delete(str filenameptr) {
        ; -- delete a file
        uword file_memory = spare_memory()
        if file_memory == 0
            return
        name_for_dos(filenameptr, &dos_name)
        prepare_name(FM_DELETE, file_memory)
        ubyte code = fm_call(1)
        internal_ok = code == 0
        if code != 0
            dos_error = code
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file
        uword file_memory = spare_memory()
        if file_memory == 0
            return
        name_for_dos(oldfileptr, &dos_name)
        name_for_dos(newfileptr, &dos_name2)
        prepare_name(FM_RENAME, file_memory)
        pokew(fm + 2, &dos_name2)
        ubyte code = fm_call(1)
        internal_ok = code == 0
        if code != 0
            dos_error = code
    }

    sub get_loadaddress(str filename) -> uword {
        ; -- the address that a B file has; 0 when it cannot be read or is no B file
        uword address = 0
        if exists(filename) and list_type == BINARY {
            name_for_dos(filename, &dos_name)
            f_close()
            prepare_name(FM_OPEN, read_memory)
            fm[2] = 1
            fm[7] = BINARY
            if fm_call(1) == 0 {
                prepare(FM_READ, read_memory)
                pokew(fm + 6, 2)
                pokew(fm + 8, &address)
                if fm_call(1) != 0
                    address = 0
                prepare(FM_CLOSE, read_memory)
                void fm_call(1)
            }
        }
        return address
    }
}
