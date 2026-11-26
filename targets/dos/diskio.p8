; File I/O routines for MS-DOS (the dos target of p8p8), through DOS's file handles
; (int $21, DOS 2.0 and later).
;
; A file's name is DOS's: "NAME.EXT", with a drive and a path before it when wanted
; ("B:\DATA\NAME.EXT").  A text line ends with a carriage return and a newline there;
; f_readline() takes either, or both, as the end of a line.
;
; NOTE: as in the llvm targets' diskio, f_readline() returns a status in place of a carry
;       flag, and load() and load_raw() return a pointer.
; One file can be open for reading and one for writing at a time.

%import textio
%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()
    ubyte dos_error = 0         ; DOS's error code of the last operation that failed

    const uword NO_HANDLE = $ffff
    uword read_handle = NO_HANDLE
    uword write_handle = NO_HANDLE
    ; what was read ahead of the file that is open for reading
    const ubyte AHEAD = 128
    ubyte[AHEAD] read_ahead
    ubyte read_pos = 0
    ubyte read_len = 0

    ; DOS's record of a directory entry that was found: 21 bytes of its own, then the
    ; attributes (21), time (22), date (24), size (26, four bytes) and the name (30)
    ubyte[43] found
    const ubyte FOUND_ATTRIBUTES = 21
    const ubyte FOUND_SIZE = 26
    const ubyte FOUND_NAME = 30
    const ubyte ATTR_DIRECTORY = 16
    const ubyte ATTR_LABEL = 8
    ubyte[80] path              ; a path that DOS gave

    ; ----- DOS's calls: a carry that comes back says that it failed, with the error's code in AX -----

    asmsub dos_open(str name @DX, ubyte mode @AL) -> uword @AX, bool @Pc {
        ; -- mode 0 to read, 1 to write, 2 for both
        %asm {{
            mov  ah, 0x3d
            int  0x21
            ret
        }}
    }

    asmsub dos_create(str name @DX) -> uword @AX, bool @Pc {
        ; -- a new file, or an existing one made empty
        %asm {{
            mov  ah, 0x3c
            xor  cx, cx
            int  0x21
            ret
        }}
    }

    asmsub dos_close(uword handle @BX) {
        %asm {{
            mov  ah, 0x3e
            int  0x21
            ret
        }}
    }

    asmsub dos_read(uword handle @BX, uword buffer @DX, uword count @CX) -> uword @AX, bool @Pc {
        ; -- how many bytes were read: fewer than asked for at the file's end
        %asm {{
            mov  ah, 0x3f
            int  0x21
            ret
        }}
    }

    asmsub dos_write(uword handle @BX, uword buffer @DX, uword count @CX) -> uword @AX, bool @Pc {
        %asm {{
            mov  ah, 0x40
            int  0x21
            ret
        }}
    }

    asmsub dos_seek(uword handle @BX, uword low @DX, uword high @CX, ubyte whence @AL) -> uword @AX, uword @DX, bool @Pc {
        ; -- move to a position counted from the start (whence 0), from where the file is (1) or from its end (2);
        ;    gives the position from the start
        %asm {{
            mov  ah, 0x42
            int  0x21
            ret
        }}
    }

    asmsub dos_name(str name @DX, ubyte function @AH) -> uword @AX, bool @Pc {
        ; -- the calls that take a name and no more: $39 make a directory, $3a remove one, $3b go to one, $41 delete a file
        %asm {{
            int  0x21
            ret
        }}
    }

    asmsub dos_attributes(str name @DX) -> uword @CX, bool @Pc {
        %asm {{
            mov  ax, 0x4300
            int  0x21
            ret
        }}
    }

    asmsub dos_rename(str oldname @DX, str newname @DI) -> uword @AX, bool @Pc {
        %asm {{
            mov  ah, 0x56
            int  0x21
            ret
        }}
    }

    asmsub dos_curdir(uword buffer @SI) -> ubyte @AL {
        ; -- the current directory of the current drive into the buffer (64 bytes), without the drive and the
        ;    first backslash; gives the drive (0 is A)
        %asm {{
            mov  ah, 0x47
            xor  dl, dl
            int  0x21
            mov  ah, 0x19
            int  0x21
            ret
        }}
    }

    asmsub dos_find(str pattern @DX, uword attributes @CX, uword record @BX) -> bool @Pc {
        ; -- the first directory entry that fits the pattern, into the record
        %asm {{
            push  dx
            mov  dx, bx
            mov  ah, 0x1a
            int  0x21
            pop  dx
            mov  ah, 0x4e
            int  0x21
            ret
        }}
    }

    asmsub dos_find_next(uword record @DX) -> bool @Pc {
        %asm {{
            mov  ah, 0x1a
            int  0x21
            mov  ah, 0x4f
            int  0x21
            ret
        }}
    }

    sub failed(uword code) {
        internal_ok = false
        dos_error = lsb(code)
    }

    ; ----- the directory -----

    sub directory() -> bool {
        ; -- print the names in the current directory, one on a line; a directory's name has a backslash after it
        return internal_list(0)
    }

    sub directory_dirs() -> bool {
        return internal_list(1)
    }

    sub directory_files() -> bool {
        return internal_list(2)
    }

    sub internal_list(ubyte kind) -> bool {
        if not lf_start_list(0)
            return true
        while lf_next_entry() {
            bool is_dir = list_filetype[0] == 'd'
            if kind == 0 or (kind == 1 and is_dir) or (kind == 2 and not is_dir) {
                txt.print(list_filename)
                if is_dir
                    txt.chrout('\\')
                txt.nl()
            }
        }
        lf_end_list()
        internal_ok = true
        return true
    }

    sub diskname() -> str {
        ; -- the label of the current drive's disk, or an empty string when it has none
        found[FOUND_NAME] = 0
        if dos_find("*.*", ATTR_LABEL, &found)
            found[FOUND_NAME] = 0
        void strings.copy(&found + FOUND_NAME, path)
        return path
    }

    ; the names of a directory, one at a time: lf_start_list(), then lf_next_entry() for as long as it is true,
    ; each time with the entry in list_filename, list_filetype ("dir" or "prg"), list_filesize and list_blocks
    ; (the size in blocks of 256 bytes, rounded up), then lf_end_list().
    str list_filename = "?" * 12
    str list_filetype = "???"
    long list_filesize = 0
    uword list_blocks = 0
    bool list_more = false

    sub lf_start_list(str pattern_ptr) -> bool {
        ; -- start a list of the names that fit the pattern ("*.TXT"); 0 or an empty pattern is all of them.
        ;    The pattern may have a drive and a path before it.
        if pattern_ptr == 0 or pattern_ptr[0] == 0
            pattern_ptr = "*.*"
        list_more = not dos_find(pattern_ptr, ATTR_DIRECTORY, &found)
        internal_ok = true
        return true
    }

    sub lf_next_entry() -> bool {
        ; -- the next entry, or false when there are no more.  The directory's own two entries "." and ".." are left out.
        while list_more {
            bool wanted = found[FOUND_NAME] != '.'
            if wanted {
                void strings.copy(&found + FOUND_NAME, list_filename)
                if found[FOUND_ATTRIBUTES] & ATTR_DIRECTORY != 0
                    void strings.copy("dir", list_filetype)
                else
                    void strings.copy("prg", list_filetype)
                list_filesize = peekl(&found + FOUND_SIZE)
                list_blocks = ((list_filesize + 255) >> 8) as uword
            }
            list_more = not dos_find_next(&found)
            if wanted
                return true
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

    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        uword handle
        bool error
        handle, error = dos_open(filenameptr, 0)
        if error {
            failed(handle)
            return false
        }
        read_handle = handle
        read_pos = 0
        read_len = 0
        internal_ok = true
        return true
    }

    sub next_byte() -> uword {
        ; -- the next byte of the file that is read, or $ffff at its end
        if read_pos == read_len {
            if read_handle == NO_HANDLE
                return $ffff
            uword count
            bool error
            count, error = dos_read(read_handle, &read_ahead, AHEAD)
            if error or count == 0
                return $ffff
            read_len = lsb(count)
            read_pos = 0
        }
        read_pos++
        return read_ahead[read_pos - 1]
    }

    sub f_read(pointer bufferpointer, pointer num_bytes) -> pointer {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        pointer actual = 0
        if read_handle == NO_HANDLE
            return 0
        ; (what was read ahead first, then the rest straight into the buffer)
        while read_pos != read_len and actual != num_bytes {
            @(bufferpointer) = read_ahead[read_pos]
            read_pos++
            bufferpointer++
            actual++
        }
        if actual != num_bytes {
            uword count
            bool error
            count, error = dos_read(read_handle, bufferpointer, num_bytes - actual)
            if error
                failed(count)
            else
                actual += count
        }
        return actual
    }

    sub f_read_all(pointer bufferpointer) -> pointer {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        pointer total = 0
        repeat {
            pointer part = f_read(bufferpointer, 16384)
            total += part
            bufferpointer += part
            if part != 16384
                return total
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
                ; (a newline that follows belongs to it; anything else is for the next read)
                data = next_byte()
                if data != $ffff and lsb(data) != '\n'
                    read_pos--
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
        ; -- end an iterative file loading session (close the file).
        if read_handle != NO_HANDLE {
            dos_close(read_handle)
            read_handle = NO_HANDLE
        }
        read_pos = 0
        read_len = 0
    }

    sub f_seek(long position) -> bool {
        ; -- go to a position, counted from the start, in the file that is open for reading
        if read_handle == NO_HANDLE
            return false
        uword low, high
        bool error
        read_pos = 0
        read_len = 0
        low, high, error = dos_seek(read_handle, lsw(position), msw(position), 0)
        return not error
    }

    sub f_tell() -> long, long {
        ; -- the position in the file that is open for reading, and the file's size
        if read_handle == NO_HANDLE
            return 0, 0
        uword low, high
        bool error
        low, high, error = dos_seek(read_handle, 0, 0, 1)
        long position = mklong2(high, low) - (read_len - read_pos)
        long size = f_size()
        return position, size
    }

    sub f_size() -> long {
        ; -- the size of the file that is open for reading
        if read_handle == NO_HANDLE
            return 0
        uword low, high
        uword end_low, end_high
        bool error
        low, high, error = dos_seek(read_handle, 0, 0, 1)
        end_low, end_high, error = dos_seek(read_handle, 0, 0, 2)
        void dos_seek(read_handle, low, high, 0)
        return mklong2(end_high, end_low)
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write; an existing file is made empty
        f_close_w()
        uword handle
        bool error
        handle, error = dos_create(filenameptr)
        if error {
            failed(handle)
            return false
        }
        write_handle = handle
        internal_ok = true
        return true
    }

    sub f_write(pointer bufferpointer, pointer num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file; false when not all of them went
        ;    (the disk is full) or no file is open
        if write_handle == NO_HANDLE
            return false
        if num_bytes == 0
            return true                 ; (DOS would cut the file off here)
        uword count
        bool error
        count, error = dos_write(write_handle, bufferpointer, num_bytes)
        if error {
            failed(count)
            return false
        }
        internal_ok = count == num_bytes
        return internal_ok
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        if write_handle != NO_HANDLE {
            dos_close(write_handle)
            write_handle = NO_HANDLE
        }
    }

    ; ----- directories, status -----

    sub name_call(str name, ubyte function) {
        uword code
        bool error
        code, error = dos_name(name, function)
        internal_ok = not error
        if error
            dos_error = lsb(code)
    }

    sub chdir(str name) {
        ; -- make a directory the current one (of its drive)
        name_call(name, $3b)
    }

    sub mkdir(str name) {
        name_call(name, $39)
    }

    sub rmdir(str name) {
        ; -- remove a directory, which must be empty
        name_call(name, $3a)
    }

    sub curdir() -> str {
        ; -- the current directory with its drive, as "C:\DIR"
        path[0] = 'A' + dos_curdir(&path + 3)
        path[1] = ':'
        path[2] = '\\'
        return path
    }

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        ; -- 0, or DOS's code of the error (2 file not found, 3 path not found, 5 access denied ...; 255 when DOS gave none)
        if internal_ok
            return 0
        if dos_error == 0
            return 255
        return dos_error
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
        ; -- delete a file
        name_call(filenameptr, $41)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file, or move it to another directory of its drive.  It fails when the new name exists.
        uword code
        bool error
        code, error = dos_rename(oldfileptr, newfileptr)
        internal_ok = not error
        if error
            dos_error = lsb(code)
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file (or directory) exists, otherwise false
        uword attributes
        bool error
        attributes, error = dos_attributes(filename)
        return not error
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
