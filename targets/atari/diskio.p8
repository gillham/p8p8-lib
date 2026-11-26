; File I/O routines for the Atari 8-bit computers (the atari target of p8p8), through
; the OS's CIO calls: they work with whatever DOS is loaded (Atari DOS 2.0S and 2.5,
; MyDOS, SpartaDOS ...) and with any other device that has files.
;
; A file's name is the DOS's: "NAME.EXT", eight letters and digits and three.  Without
; a device before it, it is on the disk drive that drivenumber says ("D1:NAME.EXT");
; a name with a colon in it is taken as it is ("D2:NAME.EXT", "H:NAME.EXT").  Small
; letters are made capitals, which is all that the DOSes take.
; A text line ends with ATASCII's end of line ($9b, which is what '\n' is here).
;
; The files are open on the IOCBs 1 (reading), 2 (writing) and 3 (the directory, and
; the calls that take a name); the screen editor has IOCB 0.
; One file can be open for reading and one for writing at a time.
; Not there: a position in a file (f_seek, f_tell): the DOSes count in sectors.
;
; NOTE: f_readline() returns a status in place of a carry flag.

%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    const ubyte READ_IOCB = $10
    const ubyte WRITE_IOCB = $20
    const ubyte NAME_IOCB = $30

    const ubyte CIO_OPEN = 3
    const ubyte CIO_GET_RECORD = 5
    const ubyte CIO_GET = 7
    const ubyte CIO_PUT = 11
    const ubyte CIO_CLOSE = 12
    const ubyte CIO_RENAME = 32
    const ubyte CIO_DELETE = 33

    const ubyte END_OF_FILE = 136

    ubyte drivenumber = 1           ; the disk drive of a name without a device, 1 to 8
    bool internal_ok = true         ; whether the last disk operation succeeded, for status() and status_code()
    ubyte cio_error = 0             ; the OS's code of the last operation that failed
    bool read_open = false
    bool write_open = false
    bool read_ended = false
    ubyte[48] spec                  ; a name as the OS wants it: with its device, and an end of line after it
    ubyte one_byte

    ; ----- the OS's calls -----

    asmsub cio(ubyte iocb @X, ubyte command @A) -> ubyte @Y {
        ; -- the command for an IOCB (its number times 16); the status comes back, 128 and more is an error
        %asm {{
            sta  $0342,x
            jmp  $e456
        }}
    }

    asmsub cio_buffer(ubyte iocb @X, uword address @AY) {
        %asm {{
            sta  $0344,x
            tya
            sta  $0345,x
            rts
        }}
    }

    asmsub cio_length(ubyte iocb @X, uword length @AY) {
        %asm {{
            sta  $0348,x
            tya
            sta  $0349,x
            rts
        }}
    }

    asmsub cio_done(ubyte iocb @X) -> uword @AY {
        ; -- how many bytes the last call moved
        %asm {{
            lda  $0349,x
            tay
            lda  $0348,x
            rts
        }}
    }

    asmsub cio_aux(ubyte iocb @X, ubyte aux1 @A) {
        %asm {{
            sta  $034a,x
            lda  #0
            sta  $034b,x
            rts
        }}
    }

    sub failed(ubyte code) {
        internal_ok = false
        cio_error = code
    }

    sub put_name(str name, ubyte at) -> ubyte {
        ; -- the name into spec from the given place on, in capitals; returns where it ends
        ubyte k = 0
        while name[k] != 0 and at < len(spec) - 2 {
            ubyte c = name[k]
            if c >= 'a' and c <= 'z'
                c -= 32
            spec[at] = c
            at++
            k++
        }
        return at
    }

    sub device(str name) -> ubyte {
        ; -- the device of a name into spec, when the name has none of its own; returns where the name goes
        ubyte k = 0
        while name[k] != 0 {
            if name[k] == ':'
                return 0
            k++
        }
        spec[0] = 'D'
        spec[1] = '0' + drivenumber
        spec[2] = ':'
        return 3
    }

    sub filespec(str name) {
        ubyte at = put_name(name, device(name))
        spec[at] = $9b
    }

    sub open(ubyte iocb, str name, ubyte mode) -> bool {
        ; -- open the name on an IOCB: 4 to read, 8 to write, 6 for the directory
        filespec(name)
        void cio(iocb, CIO_CLOSE)
        cio_buffer(iocb, &spec)
        cio_aux(iocb, mode)
        ubyte code = cio(iocb, CIO_OPEN)
        if code >= 128 {
            void cio(iocb, CIO_CLOSE)
            failed(code)
            return false
        }
        internal_ok = true
        return true
    }

    sub name_call(ubyte command) {
        ; -- a call that takes the name in spec
        void cio(NAME_IOCB, CIO_CLOSE)
        cio_buffer(NAME_IOCB, &spec)
        cio_aux(NAME_IOCB, 0)
        ubyte code = cio(NAME_IOCB, command)
        internal_ok = code < 128
        if not internal_ok
            cio_error = code
    }

    ; ----- the directory -----

    ; the names of a directory, one at a time: lf_start_list(), then lf_next_entry() for as long as it is true,
    ; each time with the entry in list_filename, list_filetype (what is after the name's dot) and list_blocks
    ; (its size in sectors), then lf_end_list().
    str list_filename = "?" * 12
    str list_filetype = "???"
    uword list_blocks = 0
    bool list_open = false
    ubyte[24] list_line

    sub lf_start_list(str pattern_ptr) -> bool {
        ; -- start a list of the names that fit the pattern ("*.TXT"); 0 or an empty pattern is all of them.
        if pattern_ptr == 0 or pattern_ptr[0] == 0
            pattern_ptr = "*.*"
        list_open = open(NAME_IOCB, pattern_ptr, 6)
        return list_open
    }

    sub lf_next_entry() -> bool {
        ; -- the next entry, or false when there are no more.
        ;    (A line of the directory is "  NAME    EXT 042", with a star before a file that is locked;
        ;    the last line begins with the number of sectors that are free.)
        if not list_open
            return false
        cio_buffer(NAME_IOCB, &list_line)
        cio_length(NAME_IOCB, len(list_line) - 1)
        ubyte code = cio(NAME_IOCB, CIO_GET_RECORD)
        if code >= 128 or list_line[0] >= '0' and list_line[0] <= '9' or list_line[1] != ' ' {
            lf_end_list()
            return false
        }
        ubyte at = 0
        ubyte k
        for k in 2 to 9 {
            if list_line[k] != ' ' {
                list_filename[at] = list_line[k]
                at++
            }
        }
        ubyte ext = 0
        for k in 10 to 12 {
            if list_line[k] != ' ' {
                if ext == 0 {
                    list_filename[at] = '.'
                    at++
                }
                list_filename[at] = list_line[k]
                at++
                list_filetype[ext] = list_line[k]
                ext++
            }
        }
        list_filename[at] = 0
        list_filetype[ext] = 0
        list_blocks = 0
        k = 14
        while list_line[k] >= '0' and list_line[k] <= '9' {
            list_blocks = list_blocks * 10 + (list_line[k] - '0')
            k++
        }
        return true
    }

    sub lf_end_list() {
        if list_open {
            void cio(NAME_IOCB, CIO_CLOSE)
            list_open = false
        }
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

    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        read_open = open(READ_IOCB, filenameptr, 4)
        read_ended = false
        return read_open
    }

    sub f_read(uword bufferpointer, uword num_bytes) -> uword {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        if not read_open or read_ended or num_bytes == 0
            return 0
        cio_buffer(READ_IOCB, bufferpointer)
        cio_length(READ_IOCB, num_bytes)
        ubyte code = cio(READ_IOCB, CIO_GET)
        if code >= 128 {
            read_ended = true
            if code != END_OF_FILE
                failed(code)
        }
        return cio_done(READ_IOCB)
    }

    sub f_read_all(uword bufferpointer) -> uword {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        uword total = 0
        repeat {
            uword part = f_read(bufferpointer, 16384)
            total += part
            bufferpointer += part
            if part != 16384
                return total
        }
    }

    sub f_readline(uword bufptr) -> ubyte, ubyte {
        ; Routine to read text lines from a text file.
        ; Reads characters from the input file UNTIL an end of line ($9b), or 0 byte, or the end of the file.
        ; The line read will be 0-terminated in the buffer (and not contain the end of line character).
        ; A line longer than 255 characters continues in the next call, so the buffer needs room for 256 bytes.
        ; Returns the length of the line (an empty line is okay and is length 0!), and a status byte:
        ; 0 when the line ended, $40 when the file ended instead, or there was an error, or no file was open.
        ubyte size = 0
        repeat {
            if f_read(&one_byte, 1) != 1 {
                @(bufptr) = 0
                return size, $40
            }
            if one_byte == $9b or one_byte == 0 {
                @(bufptr) = 0
                return size, 0
            }
            @(bufptr) = one_byte
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
            void cio(READ_IOCB, CIO_CLOSE)
            read_open = false
        }
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write.  An existing file is overwritten.
        ;    Returns true if the file is successfully opened.
        f_close_w()
        write_open = open(WRITE_IOCB, filenameptr, 8)
        return write_open
    }

    sub f_write(uword bufferpointer, uword num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        ;    Returns true if all of them were written.
        if not write_open
            return false
        if num_bytes == 0
            return true
        cio_buffer(WRITE_IOCB, bufferpointer)
        cio_length(WRITE_IOCB, num_bytes)
        ubyte code = cio(WRITE_IOCB, CIO_PUT)
        if code >= 128 {
            failed(code)
            return false
        }
        return true
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        if write_open {
            ubyte code = cio(WRITE_IOCB, CIO_CLOSE)
            if code >= 128
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
        ; -- 0, or the OS's code of the error (170 file not found, 162 disk full, 167 file locked, 138 no drive ...)
        if internal_ok
            return 0
        return cio_error
    }

    ; ----- whole files -----

    sub save(str filenameptr, uword start_address, uword savesize) -> bool {
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
    sub save_raw(str filenameptr, uword start_address, uword savesize) -> bool {
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory, skipping the 2-byte prg header in the file: at the address given,
    ; or with 0 at the address that the header says.
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    sub load(str filenameptr, uword address_override) -> uword {
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
        uword size = f_read_all(address_override)
        f_close()
        return address_override + size
    }

    ; Identical to load(), but DOES INCLUDE the first 2 bytes in the file.
    ; No program header is assumed in the file. Everything is loaded.
    sub load_raw(str filenameptr, uword start_address) -> uword {
        if not f_open(filenameptr)
            return 0
        uword size = f_read_all(start_address)
        f_close()
        return start_address + size
    }

    sub delete(str filenameptr) {
        ; -- delete a file
        filespec(filenameptr)
        name_call(CIO_DELETE)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file ("D1:OLD.EXT,NEW.EXT" is what the DOS is given: the new name has no device)
        ubyte at = put_name(oldfileptr, device(oldfileptr))
        spec[at] = ','
        at = put_name(newfileptr, at + 1)
        spec[at] = $9b
        name_call(CIO_RENAME)
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists, otherwise false
        bool was_ok = internal_ok
        bool found = open(NAME_IOCB, filename, 4)
        void cio(NAME_IOCB, CIO_CLOSE)
        internal_ok = was_ok
        return found
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
