; File I/O routines for the Atari ST (the atarist target of p8p8), through GEMDOS's file
; handles.
;
; A file's name is GEMDOS's: "NAME.EXT", with a drive and a path before it when wanted
; ("D:\DATA\NAME.EXT").  A text line ends with a carriage return and a newline there;
; f_readline() takes either, or both, as the end of a line.
;
; Addresses and sizes are longs here: a file can be longer than 64 KB, and so can what
; is read and written in one call.  save() puts the block's address before it as four
; bytes, and load() skips them.
; NOTE: f_readline() returns a status in place of a carry flag.
; One file can be open for reading and one for writing at a time.

%import textio
%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()
    long gemdos_error = 0       ; GEMDOS's code of the last operation that failed (a negative number)

    const word NO_HANDLE = -1
    word read_handle = NO_HANDLE
    word write_handle = NO_HANDLE
    ; what was read ahead of the file that is open for reading
    const ubyte AHEAD = 128
    ubyte[AHEAD] read_ahead
    ubyte read_pos = 0
    ubyte read_len = 0

    ; GEMDOS's record of a directory entry that was found: 21 bytes of its own, then the
    ; attributes (21), time (22), date (24), size (26, four bytes) and the name (30)
    ubyte[44] found
    const ubyte FOUND_ATTRIBUTES = 21
    const ubyte FOUND_SIZE = 26
    const ubyte FOUND_NAME = 30
    const ubyte ATTR_DIRECTORY = 16
    const ubyte ATTR_LABEL = 8
    ubyte[130] path             ; a path that GEMDOS gave

    ; ----- GEMDOS's calls (trap #1, the arguments on the stack): a negative result is an error's code -----

    const uword G_SETDTA = $1a
    const uword G_MKDIR = $39
    const uword G_RMDIR = $3a
    const uword G_CHDIR = $3b
    const uword G_DELETE = $41

    asmsub g_name(pointer name @A0, uword function @D0) -> long @D0 {
        ; -- the calls that take an address and no more
        %asm {{
            movem.l d2/a2,-(sp)
            move.l  a0,-(sp)
            move.w  d0,-(sp)
            trap    #1
            addq.l  #6,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_open(str name @A0, uword mode @D0) -> long @D0 {
        ; -- mode 0 to read, 1 to write, 2 for both; gives the handle
        %asm {{
            movem.l d2/a2,-(sp)
            move.w  d0,-(sp)
            move.l  a0,-(sp)
            move.w  #$3d,-(sp)
            trap    #1
            addq.l  #8,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_create(str name @A0) -> long @D0 {
        ; -- a new file, or an existing one made empty; gives the handle
        %asm {{
            movem.l d2/a2,-(sp)
            clr.w   -(sp)
            move.l  a0,-(sp)
            move.w  #$3c,-(sp)
            trap    #1
            addq.l  #8,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_close(word handle @D0) {
        %asm {{
            movem.l d2/a2,-(sp)
            move.w  d0,-(sp)
            move.w  #$3e,-(sp)
            trap    #1
            addq.l  #4,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_read(word handle @D0, pointer buffer @A0, long count @D1) -> long @D0 {
        ; -- how many bytes were read: fewer than asked for at the file's end
        %asm {{
            movem.l d2/a2,-(sp)
            move.l  a0,-(sp)
            move.l  d1,-(sp)
            move.w  d0,-(sp)
            move.w  #$3f,-(sp)
            trap    #1
            lea     12(sp),sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_write(word handle @D0, pointer buffer @A0, long count @D1) -> long @D0 {
        %asm {{
            movem.l d2/a2,-(sp)
            move.l  a0,-(sp)
            move.l  d1,-(sp)
            move.w  d0,-(sp)
            move.w  #$40,-(sp)
            trap    #1
            lea     12(sp),sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_seek(word handle @D0, long offset @D1, uword whence @A0) -> long @D0 {
        ; -- move to a position counted from the start (whence 0), from where the file is (1) or from its end (2);
        ;    gives the position from the start
        %asm {{
            movem.l d2/a2,-(sp)
            move.w  a0,-(sp)
            move.w  d0,-(sp)
            move.l  d1,-(sp)
            move.w  #$42,-(sp)
            trap    #1
            lea     10(sp),sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_attributes(str name @A0) -> long @D0 {
        %asm {{
            movem.l d2/a2,-(sp)
            clr.w   -(sp)
            clr.w   -(sp)
            move.l  a0,-(sp)
            move.w  #$43,-(sp)
            trap    #1
            lea     10(sp),sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_rename(str oldname @A0, str newname @A1) -> long @D0 {
        %asm {{
            movem.l d2/a2,-(sp)
            move.l  a1,-(sp)
            move.l  a0,-(sp)
            clr.w   -(sp)
            move.w  #$56,-(sp)
            trap    #1
            lea     12(sp),sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_find(str pattern @A0, uword attributes @D0) -> long @D0 {
        ; -- the first directory entry that fits the pattern, into the record that G_SETDTA named
        %asm {{
            movem.l d2/a2,-(sp)
            move.w  d0,-(sp)
            move.l  a0,-(sp)
            move.w  #$4e,-(sp)
            trap    #1
            addq.l  #8,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_find_next() -> long @D0 {
        %asm {{
            movem.l d2/a2,-(sp)
            move.w  #$4f,-(sp)
            trap    #1
            addq.l  #2,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    asmsub g_curdir(pointer buffer @A0) -> long @D0 {
        ; -- the current directory of the current drive into the buffer, without the drive
        ;    ("\DIR", nothing for the root); gives the drive (0 is A)
        %asm {{
            movem.l d2/a2,-(sp)
            clr.w   -(sp)
            move.l  a0,-(sp)
            move.w  #$47,-(sp)
            trap    #1
            addq.l  #8,sp
            move.w  #$19,-(sp)
            trap    #1
            addq.l  #2,sp
            movem.l (sp)+,d2/a2
            rts
        }}
    }

    sub failed(long code) {
        internal_ok = false
        gemdos_error = code
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
        void g_name(&found, G_SETDTA)
        if g_find("*.*", ATTR_LABEL) < 0
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
        void g_name(&found, G_SETDTA)
        list_more = g_find(pattern_ptr, ATTR_DIRECTORY) >= 0
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
            void g_name(&found, G_SETDTA)
            list_more = g_find_next() >= 0
            if wanted
                return true
        }
        return false
    }

    sub lf_end_list() {
        list_more = false
    }

    sub list_filenames(str pattern_ptr, pointer filenames_buffer, uword filenames_buf_size) -> ubyte {
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
        long handle = g_open(filenameptr, 0)
        if handle < 0 {
            failed(handle)
            return false
        }
        read_handle = handle as word
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
            long count = g_read(read_handle, &read_ahead, AHEAD)
            if count <= 0
                return $ffff
            read_len = count as ubyte
            read_pos = 0
        }
        read_pos++
        return read_ahead[read_pos - 1]
    }

    sub f_read(pointer bufferpointer, long num_bytes) -> long {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        long actual = 0
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
            long count = g_read(read_handle, bufferpointer, num_bytes - actual)
            if count < 0
                failed(count)
            else
                actual += count
        }
        return actual
    }

    sub f_read_all(pointer bufferpointer) -> long {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        long total = 0
        repeat {
            long part = f_read(bufferpointer, 65536)
            total += part
            bufferpointer += part
            if part != 65536
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
            g_close(read_handle)
            read_handle = NO_HANDLE
        }
        read_pos = 0
        read_len = 0
    }

    sub f_seek(long position) -> bool {
        ; -- go to a position, counted from the start, in the file that is open for reading
        if read_handle == NO_HANDLE
            return false
        read_pos = 0
        read_len = 0
        return g_seek(read_handle, position, 0) == position
    }

    sub f_tell() -> long, long {
        ; -- the position in the file that is open for reading, and the file's size
        if read_handle == NO_HANDLE
            return 0, 0
        long position = g_seek(read_handle, 0, 1) - (read_len - read_pos)
        long size = f_size()
        return position, size
    }

    sub f_size() -> long {
        ; -- the size of the file that is open for reading
        if read_handle == NO_HANDLE
            return 0
        long here = g_seek(read_handle, 0, 1)
        long end = g_seek(read_handle, 0, 2)
        void g_seek(read_handle, here, 0)
        return end
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write; an existing file is made empty
        f_close_w()
        long handle = g_create(filenameptr)
        if handle < 0 {
            failed(handle)
            return false
        }
        write_handle = handle as word
        internal_ok = true
        return true
    }

    sub f_write(pointer bufferpointer, long num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file; false when not all of them went
        ;    (the disk is full) or no file is open
        if write_handle == NO_HANDLE
            return false
        if num_bytes == 0
            return true
        long count = g_write(write_handle, bufferpointer, num_bytes)
        if count < 0 {
            failed(count)
            return false
        }
        internal_ok = count == num_bytes
        return internal_ok
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        if write_handle != NO_HANDLE {
            g_close(write_handle)
            write_handle = NO_HANDLE
        }
    }

    ; ----- directories, status -----

    sub name_call(str name, uword function) {
        long code = g_name(name, function)
        internal_ok = code >= 0
        if code < 0
            gemdos_error = code
    }

    sub chdir(str name) {
        ; -- make a directory the current one (of its drive)
        name_call(name, G_CHDIR)
    }

    sub mkdir(str name) {
        name_call(name, G_MKDIR)
    }

    sub rmdir(str name) {
        ; -- remove a directory, which must be empty
        name_call(name, G_RMDIR)
    }

    sub curdir() -> str {
        ; -- the current directory with its drive, as "C:\DIR"
        path[2] = 0
        path[0] = 'A' + (g_curdir(&path + 2) as ubyte)
        path[1] = ':'
        if path[2] == 0 {
            path[2] = '\\'
            path[3] = 0
        }
        return path
    }

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        ; -- 0, or GEMDOS's code of the error without its sign (33 file not found, 34 path not found,
        ;    36 access denied ...; 255 when GEMDOS gave none)
        if internal_ok
            return 0
        if gemdos_error == 0
            return 255
        return (-gemdos_error) as ubyte
    }

    ; ----- whole files -----

    sub save(str filenameptr, pointer start_address, long savesize) -> bool {
        ; -- save the memory block in a file, after a header with the start address (four bytes).
        ;    An existing file is overwritten. Returns true if successful.
        long header = start_address as long
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(&header, 4) and f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; like save() but omits the header.
    sub save_raw(str filenameptr, pointer start_address, long savesize) -> bool {
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory, skipping the four bytes of the header in the file: at the address given,
    ; or with 0 at the address that the header says.
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    sub load(str filenameptr, pointer address_override) -> pointer {
        long header
        if not f_open(filenameptr)
            return 0
        if f_read(&header, 4) != 4 {
            f_close()
            internal_ok = false
            return 0
        }
        if address_override == 0
            address_override = header as pointer
        long size = f_read_all(address_override)
        f_close()
        return address_override + size
    }

    ; Identical to load(), but DOES INCLUDE the first bytes in the file.
    ; No header is assumed in the file. Everything is loaded.
    sub load_raw(str filenameptr, pointer start_address) -> pointer {
        if not f_open(filenameptr)
            return 0
        long size = f_read_all(start_address)
        f_close()
        return start_address + size
    }

    sub delete(str filenameptr) {
        ; -- delete a file
        name_call(filenameptr, G_DELETE)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file, or move it to another directory of its drive.  It fails when the new name exists.
        long code = g_rename(oldfileptr, newfileptr)
        internal_ok = code >= 0
        if code < 0
            gemdos_error = code
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file (or directory) exists, otherwise false
        return g_attributes(filename) >= 0
    }

    sub get_loadaddress(str filename) -> pointer {
        ; -- the address in the header of a file that save() wrote; 0 when it cannot be read
        long header = 0
        if f_open(filename) {
            if f_read(&header, 4) != 4
                header = 0
            f_close()
        }
        return header as pointer
    }
}
