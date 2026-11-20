; File I/O routines for CP/M (the cpm target of p8p8), through the BDOS.
;
; What CP/M 2.2 is, shows here:
; - A file is a number of records of 128 bytes; its length in bytes is not kept.  A
;   text file ends with the byte 26 (Ctrl-Z) when it does not fill its last record:
;   f_readline() stops there, and f_close_w() fills the last record of a file with it.
;   f_read() and f_read_all() give the bytes of whole records as they are, so a file
;   that was written here comes back up to 127 bytes longer.
; - A name is 8 characters, a dot and 3, in capitals, with a drive before it at will
;   ("B:NAME.EXT"); ? stands for any character and * for any rest.
; - There are no directories below a drive: chdir(), mkdir() and rmdir() do nothing.
;
; NOTE: as in the llvm targets' diskio, f_readline() returns a status in place of a carry
;       flag, and load() and load_raw() return a pointer.
; One file can be open for reading and one for writing at a time.

%import textio
%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    const ubyte RECORD = 128
    const ubyte END_OF_TEXT = 26

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()

    ; a file control block is 36 bytes: the drive, the name (8 and 3), and the BDOS's own
    ubyte[36] read_fcb
    ubyte[36] write_fcb
    ubyte[36] other_fcb         ; for delete, rename, exists and the directory
    ubyte[RECORD] read_record
    ubyte[RECORD] write_record
    ubyte[RECORD] other_record
    ubyte read_at = RECORD      ; the next byte of read_record; RECORD: none left
    ubyte write_at = 0          ; the bytes in write_record
    bool reading = false
    bool writing = false
    bool read_ended = true

    sub bdos(ubyte function, uword parameter) -> ubyte {
        ; -- calls the BDOS (at 5) with the function's number in C and its parameter in DE; what it gives in A
        ubyte @shared answer
        %asm {{
            ld  a,(_diskio_bdos_function)
            ld  c,a
            ld  de,(_diskio_bdos_parameter)
            call  5
            ld  (_diskio_bdos_answer),a
        }}
        return answer
    }

    sub set_fcb(^^ubyte fcb, str name) {
        ; -- the file control block for a name: "B:NAME.EXT", in any case, with ? and *
        ubyte k
        ubyte at = 0
        sys.memset(fcb, 36, 0)
        for k in 1 to 11
            fcb[k] = ' '
        if name[0] != 0 and name[1] == ':' {
            fcb[0] = (strings.upperchar(name[0]) - 'A' + 1) & 31
            at = 2
        }
        k = 1
        while name[at] != 0 and name[at] != '.' {
            if name[at] == '*' {
                while k <= 8 {
                    fcb[k] = '?'
                    k++
                }
            }
            else if k <= 8 {
                fcb[k] = strings.upperchar(name[at])
                k++
            }
            at++
        }
        if name[at] == '.' {
            at++
            k = 9
            while name[at] != 0 {
                if name[at] == '*' {
                    while k <= 11 {
                        fcb[k] = '?'
                        k++
                    }
                }
                else if k <= 11 {
                    fcb[k] = strings.upperchar(name[at])
                    k++
                }
                at++
            }
        }
    }


    ; ----- the directory -----

    sub directory() -> bool {
        ; -- prints the names of the files on the current drive, one on a line
        ubyte found
        ubyte k
        set_fcb(other_fcb, "*.*")
        void bdos(26, &other_record)
        found = bdos(17, &other_fcb)
        while found != 255 {
            ; (the BDOS says which of the four entries in the record it is)
            uword offset = found & 3
            offset *= 32
            ^^ubyte entry = &other_record + offset
            for k in 1 to 8 {
                if entry[k] & 127 != ' '
                    txt.chrout(entry[k] & 127)
            }
            if entry[9] & 127 != ' ' {
                txt.chrout('.')
                for k in 9 to 11 {
                    if entry[k] & 127 != ' '
                        txt.chrout(entry[k] & 127)
                }
            }
            txt.nl()
            found = bdos(18, &other_fcb)
        }
        internal_ok = true
        return true
    }

    sub directory_dirs() -> bool {
        ; -- CP/M has no directories below a drive: nothing is printed
        return true
    }

    sub directory_files() -> bool {
        return directory()
    }

    sub diskname() -> str {
        ; -- a CP/M disk has no name
        return ""
    }


    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        set_fcb(read_fcb, filenameptr)
        internal_ok = bdos(15, &read_fcb) != 255
        reading = internal_ok
        read_at = RECORD
        read_ended = not internal_ok
        return internal_ok
    }

    sub next_record() -> bool {
        ; -- the next record of the file that is read; false at its end
        if read_ended
            return false
        void bdos(26, &read_record)
        if bdos(20, &read_fcb) != 0 {
            read_ended = true
            return false
        }
        read_at = 0
        return true
    }

    sub f_read(pointer bufferpointer, pointer num_bytes) -> pointer {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.  (the bytes of whole records: see the top of this file)
        pointer actual = 0
        while actual != num_bytes {
            if read_at == RECORD {
                if not next_record()
                    return actual
            }
            uword part = RECORD - read_at
            if part > num_bytes - actual
                part = num_bytes - actual
            sys.memcopy(&read_record + read_at, bufferpointer, part)
            bufferpointer += part
            actual += part
            read_at += lsb(part)
        }
        return actual
    }

    sub f_read_all(pointer bufferpointer) -> pointer {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        pointer actual = 0
        repeat {
            if read_at == RECORD {
                if not next_record()
                    return actual
            }
            uword part = RECORD - read_at
            sys.memcopy(&read_record + read_at, bufferpointer, part)
            bufferpointer += part
            actual += part
            read_at = RECORD
        }
    }

    sub f_readline(pointer bufptr) -> ubyte, ubyte {
        ; Routine to read text lines from a text file.
        ; Reads characters from the input file UNTIL a newline or return character, or 0 byte, or the end of the file
        ; (a Ctrl-Z, or the last record).  A return character with a newline after it, as CP/M ends a line, is one end.
        ; The line read will be 0-terminated in the buffer (and not contain the end of line character).
        ; A line longer than 255 characters continues in the next call, so the buffer needs room for 256 bytes.
        ; Returns the length of the line (an empty line is okay and is length 0!), and a status byte:
        ; 0 when the line ended, $40 when the file ended instead, or there was an error, or no file was open.
        ubyte size = 0
        ubyte char
        repeat {
            if read_at == RECORD {
                if not next_record() {
                    @(bufptr) = 0
                    return size, $40
                }
            }
            char = read_record[read_at]
            if char == END_OF_TEXT {
                read_ended = true
                read_at = RECORD
                @(bufptr) = 0
                return size, $40
            }
            read_at++
            if char == '\r' {
                ; (the newline that follows belongs to it)
                if read_at == RECORD
                    void next_record()
                if read_at != RECORD and read_record[read_at] == '\n'
                    read_at++
                @(bufptr) = 0
                return size, 0
            }
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
        ; -- end an iterative file loading session (close channels).
        ;    it is safe to call this multiple times, or when no file is open for reading.
        if reading
            void bdos(16, &read_fcb)
        reading = false
        read_ended = true
        read_at = RECORD
    }

    sub f_seek(long position) -> bool {
        ; -- not there on CP/M yet
        return false
    }

    sub f_tell() -> long, long {
        return 0, 0
    }

    sub f_size() -> long {
        return 0
    }


    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write; a file of that name is replaced
        ;    Returns true if the file is successfully created.
        f_close_w()
        set_fcb(write_fcb, filenameptr)
        void bdos(19, &write_fcb)
        set_fcb(write_fcb, filenameptr)
        internal_ok = bdos(22, &write_fcb) != 255
        writing = internal_ok
        write_at = 0
        return internal_ok
    }

    sub write_out() -> bool {
        ; -- the record that was filled goes to the file
        void bdos(26, &write_record)
        write_at = 0
        return bdos(21, &write_fcb) == 0
    }

    sub f_write(pointer bufferpointer, pointer num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        if not writing
            return false
        while num_bytes != 0 {
            uword part = RECORD - write_at
            if part > num_bytes
                part = num_bytes
            sys.memcopy(bufferpointer, &write_record + write_at, part)
            bufferpointer += part
            num_bytes -= part
            write_at += lsb(part)
            if write_at == RECORD {
                if not write_out() {
                    internal_ok = false
                    return false
                }
            }
        }
        return true
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close channels).
        ;    The last record is filled with the end-of-text byte, as CP/M's text files are.
        if not writing
            return
        if write_at != 0 {
            sys.memset(&write_record + write_at, RECORD - write_at, END_OF_TEXT)
            if not write_out()
                internal_ok = false
        }
        if bdos(16, &write_fcb) == 255
            internal_ok = false
        writing = false
    }


    ; ----- directories, status -----

    sub chdir(str path) {
    }

    sub mkdir(str name) {
    }

    sub rmdir(str name) {
    }

    sub curdir() -> str {
        return ""
    }

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        if internal_ok
            return 0
        return 255
    }

    sub last_drive() -> ubyte {
        ; -- the current drive: 0 is A
        return bdos(25, 0)
    }


    ; ----- whole files -----

    sub save(str filenameptr, pointer start_address, pointer savesize) -> bool {
        ; -- save the memory block in a file, after a 2-byte prg header with the start address.
        ;    An existing file is overwritten. Returns true if successful.
        uword header = start_address
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(&header, 2) and f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; like save() but omits the 2 byte prg header.
    sub save_raw(str filenameptr, pointer start_address, pointer savesize) -> bool {
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory, skipping the 2-byte prg header in the file: at the address given,
    ; or with 0 at the address that the header says.
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    ; (The file's bytes are those of its whole records: up to 127 more than were saved.)
    sub load(str filenameptr, pointer address_override) -> pointer {
        uword header
        if not f_open(filenameptr)
            return 0
        if f_read(&header, 2) != 2 {
            f_close()
            internal_ok = false
            return 0
        }
        if address_override == 0
            address_override = header
        pointer size = f_read_all(address_override)
        f_close()
        return address_override + size
    }

    ; Identical to load(), but DOES INCLUDE the first 2 bytes in the file.
    ; No program header is assumed in the file. Everything is loaded.
    sub load_raw(str filenameptr, pointer start_address) -> pointer {
        if not f_open(filenameptr)
            return 0
        pointer size = f_read_all(start_address)
        f_close()
        return start_address + size
    }

    sub delete(str filenameptr) {
        ; -- delete a file on the drive
        set_fcb(other_fcb, filenameptr)
        internal_ok = bdos(19, &other_fcb) != 255
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file on the drive: the new name is in the second half of the control block
        set_fcb(other_fcb, newfileptr)
        sys.memcopy(&other_fcb, &other_fcb + 16, 16)
        ubyte[16] new_half
        sys.memcopy(&other_fcb + 16, &new_half, 16)
        set_fcb(other_fcb, oldfileptr)
        sys.memcopy(&new_half, &other_fcb + 16, 16)
        internal_ok = bdos(23, &other_fcb) != 255
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists on the disk, otherwise false
        set_fcb(other_fcb, filename)
        void bdos(26, &other_record)
        return bdos(17, &other_fcb) != 255
    }

    sub get_loadaddress(str filename) -> uword {
        ; -- the address in the 2-byte header of a file that save() wrote; 0 when it cannot be read
        uword header = 0
        if f_open(filename) {
            if f_read(&header, 2) != 2
                header = 0
            f_close()
        }
        return header
    }
}
