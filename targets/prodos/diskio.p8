; File I/O routines for the Apple II with ProDOS (the prodos target of p8p8), through
; ProDOS's machine language interface (the MLI).
;
; A file's name is ProDOS's: up to 15 letters, digits and periods, the first a letter.
; A name with slashes is a path ("/VOLUME/DIR/NAME", or "DIR/NAME" from the prefix).
; Small letters are made capitals.  A name without a volume is in the prefix, which is
; what chdir() sets and curdir() gives; when the program starts without one, the
; volume of the disk that was used last becomes the prefix.
;
; ProDOS keeps the length of a file, so every byte comes back as it was written.
; What f_open_w makes has the type that file_type says: TXT at first (a text file is
; plain ASCII there, a line ends with a carriage return, which '\n' is here), or BIN.
; save() makes a BIN file with its address as the file's auxiliary type, as BSAVE does.
;
; One file can be open for reading and one for writing at a time.  The list of a
; directory borrows the memory of the file that is not open: with both open, it fails.
;
; NOTE: f_readline() returns a status in place of a carry flag.

%import syslib
%import strings

diskio {
    %option no_symbol_prefixing, ignore_unused

    const ubyte TXT = $04
    const ubyte BIN = $06
    const ubyte DIRECTORY = $0f
    const ubyte SYSTEM = $ff

    ; the MLI's calls
    const ubyte MLI_CREATE = $c0
    const ubyte MLI_DESTROY = $c1
    const ubyte MLI_RENAME = $c2
    const ubyte MLI_GET_FILE_INFO = $c4
    const ubyte MLI_ONLINE = $c5
    const ubyte MLI_SET_PREFIX = $c6
    const ubyte MLI_GET_PREFIX = $c7
    const ubyte MLI_OPEN = $c8
    const ubyte MLI_READ = $ca
    const ubyte MLI_WRITE = $cb
    const ubyte MLI_CLOSE = $cc
    const ubyte MLI_SET_MARK = $ce
    const ubyte MLI_GET_MARK = $cf
    const ubyte MLI_GET_EOF = $d1
    ; its errors
    const ubyte ERR_END_OF_FILE = $4c
    const ubyte ERR_NOT_FOUND = $46
    const ubyte ERR_TOO_MANY_OPEN = $42

    ubyte file_type = TXT           ; what f_open_w makes: TXT, BIN or another of ProDOS's types
    uword aux_type = 0              ; and its auxiliary type (a BIN file's address)
    bool internal_ok = true         ; whether the last disk operation succeeded, for status() and status_code()
    ubyte mli_error = 0             ; the MLI's code of the last operation that failed

    ; ProDOS wants 1024 bytes for every open file, at the beginning of a page
    uword read_memory = memory("p8_diskio_read", 1024, 256)
    uword write_memory = memory("p8_diskio_write", 1024, 256)
    ubyte read_ref = 0              ; ProDOS's number of the file that is open, or 0
    ubyte write_ref = 0
    ubyte list_ref = 0

    ; what was read ahead of the file that is open for reading
    const ubyte AHEAD = 64
    ubyte[AHEAD] read_ahead
    ubyte read_pos = 0
    ubyte read_len = 0

    ubyte[18] par                   ; the parameters of a call
    ubyte[66] path                  ; a name as the MLI wants it: its length, then its characters
    ubyte[66] path2
    bool prefix_checked = false

    asmsub mli(ubyte command @A, uword parameters @XY) -> ubyte @A {
        ; -- a call of the MLI; returns 0 or its error
        %asm {{
            sta  _command
            stx  _parameters
            sty  _parameters+1
            jsr  $bf00
_command    .byte  0
_parameters .word  0
            rts
        }}
    }

    sub mli_call(ubyte command) -> bool {
        ; -- the call with what is in par; false when it failed
        ubyte code = mli(command, &par)
        if code != 0 {
            internal_ok = false
            mli_error = code
            return false
        }
        return true
    }

    sub set_path(str name, uword target) {
        ; -- the name with its length before it, in capitals
        ubyte k = 0
        while k < 64 and name[k] != 0 {
            ubyte c = name[k]
            if c >= 'a' and c <= 'z'
                c -= 32
            target[k + 1] = c
            k++
        }
        target[0] = k
    }

    sub prefix() {
        ; -- a program that ProDOS started from a disk may have no prefix: then a name
        ;    without a volume is no file.  The volume of the disk used last becomes it.
        if prefix_checked
            return
        prefix_checked = true
        par[0] = 1
        pokew(&par + 1, &path)
        if mli(MLI_GET_PREFIX, &par) == 0 and path[0] != 0
            return
        par[0] = 2
        par[1] = @($bf30)           ; (the slot and drive of the last access)
        pokew(&par + 2, &path + 1)
        if mli(MLI_ONLINE, &par) == 0 {
            ; (the first byte has the drive and the length of the name, which follows it)
            path[0] = (path[1] & 15) + 1
            path[1] = '/'
            par[0] = 1
            pokew(&par + 1, &path)
            void mli(MLI_SET_PREFIX, &par)
        }
    }

    sub named(str name) {
        ; -- the parameters of a call that takes a name
        prefix()
        set_path(name, &path)
        pokew(&par + 1, &path)
    }

    sub open(str name, uword file_memory) -> ubyte {
        ; -- open a file; returns ProDOS's number for it, or 0
        named(name)
        par[0] = 3
        pokew(&par + 3, file_memory)
        if not mli_call(MLI_OPEN)
            return 0
        internal_ok = true
        return par[5]
    }

    sub close(ubyte ref) {
        par[0] = 1
        par[1] = ref
        void mli_call(MLI_CLOSE)
    }

    sub file_info(str name) -> bool {
        ; -- what the directory has of a file into par: its type (4), auxiliary type (5), kind (7), blocks (8)
        named(name)
        par[0] = 10
        return mli(MLI_GET_FILE_INFO, &par) == 0
    }

    ; ----- the directory -----

    ; the names of the directory that is the prefix, one at a time: lf_start_list(), then lf_next_entry()
    ; for as long as it is true, each time with the entry in list_filename, list_filetype (TXT, BIN, SYS,
    ; DIR, BAS, or $ and ProDOS's number of the type), list_type (that number), list_blocks (its size in
    ; blocks of 512 bytes) and list_filesize (in bytes), then lf_end_list().
    str list_filename = "?" * 15
    str list_filetype = "???"
    ubyte list_type = 0
    uword list_blocks = 0
    long list_filesize = 0
    str list_pattern = "?" * 15
    ubyte[40] list_entry
    ubyte list_slot = 0
    ubyte list_entry_size = 39
    ubyte list_per_block = 13

    sub list_read(uword count) -> bool {
        par[0] = 4
        par[1] = list_ref
        pokew(&par + 2, &list_entry)
        pokew(&par + 4, count)
        return mli(MLI_READ, &par) == 0 and peekw(&par + 6) == count
    }

    sub lf_start_list(str pattern_ptr) -> bool {
        ; -- start a list of the names that fit the pattern ("*.TXT", with * and ?); 0 or an empty pattern is all of them.
        lf_end_list()
        list_pattern[0] = 0
        if pattern_ptr != 0 {
            set_path(pattern_ptr, &path2)
            ubyte k
            for k in 0 to 14
                list_pattern[k] = path2[k + 1]
            if path2[0] < 15
                list_pattern[path2[0]] = 0
        }
        uword file_memory = write_memory
        if write_ref != 0 {
            file_memory = read_memory
            if read_ref != 0 {
                internal_ok = false
                mli_error = ERR_TOO_MANY_OPEN
                return false
            }
        }
        ; (the directory is a file: the prefix without the slash that ends it)
        prefix()
        par[0] = 1
        pokew(&par + 1, &path)
        if not mli_call(MLI_GET_PREFIX)
            return false
        if path[0] > 1
            path[0]--
        par[0] = 3
        pokew(&par + 3, file_memory)
        if not mli_call(MLI_OPEN)
            return false
        list_ref = par[5]
        ; (a block begins with four bytes that link it to its neighbours; the first
        ;  entry of the first block is the directory's own)
        if not list_read(4 + 39) {
            lf_end_list()
            return false
        }
        list_entry_size = list_entry[4 + $1f]
        list_per_block = list_entry[4 + $20]
        if list_entry_size < 39 or list_entry_size > 40 or list_per_block == 0 {
            lf_end_list()
            return false
        }
        if list_entry_size == 40
            void list_read(1)
        list_slot = 1
        internal_ok = true
        return true
    }

    sub lf_next_entry() -> bool {
        ; -- the next entry, or false when there are no more.
        while list_ref != 0 {
            if list_slot == list_per_block {
                ; (what is left of the block, and the next one's four bytes)
                if not list_read(512 - (list_per_block as uword) * list_entry_size)
                    break
                list_slot = 0
            }
            list_slot++
            if not list_read(list_entry_size)
                break
            ubyte length = list_entry[0] & 15
            if length != 0 {
                ubyte k
                for k in 0 to 14
                    list_filename[k] = list_entry[k + 1]
                list_filename[length] = 0
                list_type = list_entry[$10]
                list_blocks = peekw(&list_entry + $13)
                list_filesize = mklong2(list_entry[$17] as uword, peekw(&list_entry + $15))
                when list_type {
                    TXT -> void strings.copy("TXT", list_filetype)
                    BIN -> void strings.copy("BIN", list_filetype)
                    DIRECTORY -> void strings.copy("DIR", list_filetype)
                    SYSTEM -> void strings.copy("SYS", list_filetype)
                    $fc -> void strings.copy("BAS", list_filetype)
                    else -> {
                        list_filetype[0] = '$'
                        list_filetype[1] = hex_digit(list_type >> 4)
                        list_filetype[2] = hex_digit(list_type & 15)
                    }
                }
                if list_pattern[0] == 0 or strings.pattern_match(list_filename, list_pattern)
                    return true
            }
        }
        lf_end_list()
        return false
    }

    sub hex_digit(ubyte value) -> ubyte {
        if value < 10
            return '0' + value
        return 'A' - 10 + value
    }

    sub lf_end_list() {
        if list_ref != 0 {
            par[0] = 1
            par[1] = list_ref
            void mli(MLI_CLOSE, &par)
            list_ref = 0
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
        read_ref = open(filenameptr, read_memory)
        return read_ref != 0
    }

    sub read_bytes(uword bufferpointer, uword num_bytes) -> uword {
        if read_ref == 0 or num_bytes == 0
            return 0
        par[0] = 4
        par[1] = read_ref
        pokew(&par + 2, bufferpointer)
        pokew(&par + 4, num_bytes)
        ubyte code = mli(MLI_READ, &par)
        if code != 0 {
            if code != ERR_END_OF_FILE {
                internal_ok = false
                mli_error = code
            }
            return 0
        }
        return peekw(&par + 6)
    }

    sub next_byte() -> uword {
        ; -- the next byte of the file that is read, or $ffff at its end
        if read_pos == read_len {
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
        if read_ref != 0 {
            close(read_ref)
            read_ref = 0
        }
        read_pos = 0
        read_len = 0
    }

    sub f_seek(long position) -> bool {
        ; -- go to a position, counted from the start, in the file that is open for reading
        if read_ref == 0
            return false
        par[0] = 2
        par[1] = read_ref
        pokel(&par + 2, position)
        read_pos = 0
        read_len = 0
        return mli_call(MLI_SET_MARK)
    }

    sub f_tell() -> long, long {
        ; -- the position in the file that is open for reading, and its size; 0, 0 when none is open
        if read_ref == 0
            return 0, 0
        par[0] = 2
        par[1] = read_ref
        par[5] = 0
        if not mli_call(MLI_GET_MARK)
            return 0, 0
        long position = peekl(&par + 2) - (read_len - read_pos)
        par[5] = 0
        if not mli_call(MLI_GET_EOF)
            return 0, 0
        return position, peekl(&par + 2)
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write, of the type that file_type says.
        ;    An existing file is overwritten.  Returns true if the file is successfully opened.
        f_close_w()
        named(filenameptr)
        par[0] = 1
        void mli(MLI_DESTROY, &par)
        par[0] = 7
        par[3] = $c3                ; (it may be read, written, renamed and deleted)
        par[4] = file_type
        pokew(&par + 5, aux_type)
        par[7] = 1                  ; (a file, not a directory)
        pokew(&par + 8, 0)
        pokew(&par + 10, 0)
        if not mli_call(MLI_CREATE)
            return false
        write_ref = open(filenameptr, write_memory)
        return write_ref != 0
    }

    sub f_write(uword bufferpointer, uword num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        ;    Returns true if all of them were written.
        if write_ref == 0
            return false
        if num_bytes == 0
            return true
        par[0] = 4
        par[1] = write_ref
        pokew(&par + 2, bufferpointer)
        pokew(&par + 4, num_bytes)
        return mli_call(MLI_WRITE)
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        if write_ref != 0 {
            close(write_ref)
            write_ref = 0
        }
    }

    ; ----- directories, status -----

    sub chdir(str name) {
        ; -- make a directory the prefix ("/VOLUME", "/VOLUME/DIR", or "DIR" in the prefix that is)
        named(name)
        par[0] = 1
        internal_ok = mli_call(MLI_SET_PREFIX)
    }

    sub mkdir(str name) {
        named(name)
        par[0] = 7
        par[3] = $c3
        par[4] = DIRECTORY
        pokew(&par + 5, 0)
        par[7] = $0d                ; (a directory)
        pokew(&par + 8, 0)
        pokew(&par + 10, 0)
        internal_ok = mli_call(MLI_CREATE)
    }

    sub rmdir(str name) {
        ; -- remove a directory, which must be empty
        delete(name)
    }

    sub curdir() -> str {
        ; -- the prefix, as "/VOLUME/DIR/"
        prefix()
        par[0] = 1
        pokew(&par + 1, &path2)
        path2[0] = 0
        void mli_call(MLI_GET_PREFIX)
        path2[path2[0] + 1] = 0
        return &path2 + 1
    }

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        ; -- 0, or the MLI's code of the error ($46 file not found, $47 the name is there already,
        ;    $48 disk full, $2b write protected, $4e the file is locked, $40 no such name, $27 I/O error)
        if internal_ok
            return 0
        return mli_error
    }

    ; ----- whole files -----

    sub save(str filenameptr, uword start_address, uword savesize) -> bool {
        ; -- save the memory block in a BIN file with its address, as BSAVE does: BLOAD puts it back.
        ;    An existing file is overwritten. Returns true if successful.
        ubyte was_type = file_type
        uword was_aux = aux_type
        file_type = BIN
        aux_type = start_address
        bool opened = f_open_w(filenameptr)
        file_type = was_type
        aux_type = was_aux
        if not opened
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; like save(), with no address: a file of the type that file_type says.
    sub save_raw(str filenameptr, uword start_address, uword savesize) -> bool {
        if not f_open_w(filenameptr)
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory: at the address given, or with 0 at the address that the file has
    ; (its auxiliary type, which is where save() and BSAVE put it).
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    sub load(str filenameptr, uword address_override) -> uword {
        if address_override == 0 {
            address_override = get_loadaddress(filenameptr)
            if address_override == 0
                return 0
        }
        return load_raw(filenameptr, address_override)
    }

    ; Load the given file in memory at the address given.
    sub load_raw(str filenameptr, uword start_address) -> uword {
        if not f_open(filenameptr)
            return 0
        uword size = f_read_all(start_address)
        f_close()
        return start_address + size
    }

    sub delete(str filenameptr) {
        ; -- delete a file (or a directory that is empty)
        named(filenameptr)
        par[0] = 1
        internal_ok = mli_call(MLI_DESTROY)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file; both names in the same directory
        named(oldfileptr)
        set_path(newfileptr, &path2)
        par[0] = 2
        pokew(&par + 3, &path2)
        internal_ok = mli_call(MLI_RENAME)
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file (or directory) exists, otherwise false
        return file_info(filename)
    }

    sub get_loadaddress(str filename) -> uword {
        ; -- the address that a file has (its auxiliary type); 0 when there is no such file
        if file_info(filename)
            return peekw(&par + 5)
        return 0
    }
}
