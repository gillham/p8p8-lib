; File I/O routines for the TRS-80 targets of p8p8, as far as they are the same for the
; Model I and III DOSes (TRSDOS 2.3 and 1.3, LDOS 5) and the Model 4's (TRSDOS 6,
; LS-DOS 6).  The target's own diskio module has the calls of its DOS: fspec,
; open_existing, open_new, close_file, kill, get_byte, put_byte and command, and the
; command that lists the directory.
;
; A file's name is NAME/EXT.PASSWORD:DRIVE for these DOSes.  A name as other machines
; write it works too: the first dot becomes the slash ("data.txt" is DATA/TXT), and
; the name is put in capitals.  A drive is given as a colon and its number at the end.
; A text line ends with a carriage return; f_readline() takes a newline after it as
; part of the same end, so text written with either convention reads the same.
;
; NOTE: as in the llvm targets' diskio, f_readline() returns a status in place of a carry
;       flag, and load() and load_raw() return a pointer.
; One file can be open for reading and one for writing at a time.

%import textio
%import syslib
%import strings

diskio {
    %option merge, no_symbol_prefixing, ignore_unused

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()

    ; a file control block (50 bytes is the longest, TRSDOS 1.3's) and the DOS's sector buffer for it
    ubyte[50] read_fcb
    ubyte[50] write_fcb
    ubyte[50] other_fcb
    ubyte[256] read_sector
    ubyte[256] write_sector
    ubyte[34] spec              ; a file's name as the DOS wants it, with a carriage return at its end
    bool reading = false
    bool writing = false
    uword held = $ffff          ; a byte that was read ahead, or $ffff for none

    sub set_spec(str name) {
        ; -- the name for the DOS: capitals, the first dot a slash, a carriage return at the end
        ubyte k = 0
        bool dotted = false
        while name[k] != 0 and k < 32 {
            ubyte char = strings.upperchar(name[k])
            if char == '.' and not dotted {
                char = '/'
                dotted = true
            }
            if char == '/'
                dotted = true
            spec[k] = char
            k++
        }
        spec[k] = 13
    }

    sub prepare(^^ubyte fcb, str name) -> bool {
        ; -- the file control block for a name; false when the DOS does not take the name
        set_spec(name)
        return fspec(spec, fcb)
    }


    ; ----- the directory -----

    sub directory() -> bool {
        ; -- the DOS's own directory, as its DIR command prints it (the target's module says which command)
        command(directory_command)
        internal_ok = true
        return true
    }

    sub directory_dirs() -> bool {
        ; -- these DOSes have no directories below a drive: nothing is printed
        return true
    }

    sub directory_files() -> bool {
        return directory()
    }

    sub diskname() -> str {
        return ""
    }


    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        internal_ok = prepare(read_fcb, filenameptr) and open_existing(read_fcb, read_sector)
        reading = internal_ok
        held = $ffff
        return internal_ok
    }

    sub next_byte() -> uword {
        ; -- the next byte of the file that is read, or $ffff at its end
        if not reading
            return $ffff
        if held != $ffff {
            uword first = held
            held = $ffff
            return first
        }
        return get_byte(read_fcb)
    }

    sub f_read(pointer bufferpointer, pointer num_bytes) -> pointer {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        pointer actual = 0
        while actual != num_bytes {
            uword data = next_byte()
            if data == $ffff
                return actual
            @(bufferpointer) = lsb(data)
            bufferpointer++
            actual++
        }
        return actual
    }

    sub f_read_all(pointer bufferpointer) -> pointer {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        pointer actual = 0
        repeat {
            uword data = next_byte()
            if data == $ffff
                return actual
            @(bufferpointer) = lsb(data)
            bufferpointer++
            actual++
        }
    }

    sub f_readline(pointer bufptr) -> ubyte, ubyte {
        ; Routine to read text lines from a text file.
        ; Reads characters from the input file UNTIL a newline or return character, or 0 byte, or the end of the file.
        ; A return character with a newline after it is one end of a line.
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
            if char == '\r' {
                ; (a newline that follows belongs to it; anything else is kept for the next read)
                data = next_byte()
                if data != $ffff and lsb(data) != '\n'
                    held = data
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
            close_file(read_fcb)
        reading = false
        held = $ffff
    }

    sub f_seek(long position) -> bool {
        ; -- not there on the TRS-80 yet
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
        if not prepare(write_fcb, filenameptr) {
            internal_ok = false
            return false
        }
        ; (a file of this name is removed first: the DOS would write into it and leave the rest)
        if open_existing(write_fcb, write_sector)
            void kill(write_fcb)
        internal_ok = prepare(write_fcb, filenameptr) and open_new(write_fcb, write_sector)
        writing = internal_ok
        return internal_ok
    }

    sub f_write(pointer bufferpointer, pointer num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        if not writing
            return false
        while num_bytes != 0 {
            if not put_byte(write_fcb, @(bufferpointer)) {
                internal_ok = false
                return false
            }
            bufferpointer++
            num_bytes--
        }
        return true
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close channels).
        if writing
            close_file(write_fcb)
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
        internal_ok = prepare(other_fcb, filenameptr) and open_existing(other_fcb, read_sector) and kill(other_fcb)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file.  It fails when the new name exists.  (The files that were open for reading
        ;    and writing are closed.)  With the DOS's own call where the target's module has it
        ;    (HAS_RENAME, dos_rename: the Model 4).  No call of the Model I and III DOSes does it for
        ;    every one of them: there the file is copied to the new name and the old one deleted, so
        ;    there must be room for the copy.
        if HAS_RENAME {
            f_close()
            f_close_w()
            if exists(newfileptr) or not prepare(other_fcb, oldfileptr) {
                internal_ok = false
                return
            }
            set_spec(newfileptr)
            internal_ok = dos_rename(other_fcb, spec)
            return
        }
        if exists(newfileptr) or not f_open(oldfileptr) {
            internal_ok = false
            return
        }
        if not f_open_w(newfileptr) {
            f_close()
            internal_ok = false
            return
        }
        bool copied = true
        repeat {
            uword data = next_byte()
            if data == $ffff
                break
            if not put_byte(write_fcb, lsb(data)) {
                copied = false
                break
            }
        }
        f_close()
        f_close_w()
        if copied
            delete(oldfileptr)
        else {
            delete(newfileptr)
            internal_ok = false
        }
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists on the disk, otherwise false
        if prepare(other_fcb, filename) and open_existing(other_fcb, read_sector) {
            close_file(other_fcb)
            return true
        }
        return false
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
