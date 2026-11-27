; File I/O routines for a 68000 Macintosh (the macplus target of p8p8), through the
; File Manager.
;
; A file's name is the Macintosh's: up to 31 characters, capitals and small letters
; being the same.  A name alone is a file in the current folder, which is the
; application's own when the program starts.  ":Folder:name" goes down from there,
; "::name" up, and "Disk:Folder:name" names it from the disk.  chdir("..") goes up
; one folder, as on the other machines.
;
; Only a file's data fork is read and written.  A new file gets the type and the
; creator in file_type and file_creator: a text file of TeachText's, unless the
; program sets others.  A text line ends with a carriage return on a Macintosh;
; f_readline() takes that, a newline, or both, as the end of a line.
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
    word mac_error = 0          ; the File Manager's code of the last operation that failed (a negative number)

    long file_type = $54455854      ; "TEXT": what a file that is made here is,
    long file_creator = $74747874   ; "ttxt": and whose (TeachText's)

    const uword NO_FILE = 0
    uword read_file = NO_FILE       ; the File Manager's reference numbers of the open files
    uword write_file = NO_FILE
    ; what was read ahead of the file that is open for reading
    const ubyte AHEAD = 128
    ubyte[AHEAD] read_ahead
    ubyte read_pos = 0
    ubyte read_len = 0

    ubyte[256] name1            ; a name as the system wants it: its length, then its characters
    ubyte[256] name2
    ubyte[256] path             ; a path that is given to the program

    const word ERR_EOF = -39
    const word ERR_EXISTS = -48

    ; ----- the File Manager's calls, with the parameter block macos.pb (see syslib) -----

    sub pascal(str name, pointer buffer) {
        ; -- the name with its length before it; ".." is the folder above ("::")
        ubyte length = strings.length(name)
        if length == 2 and name[0] == '.' and name[1] == '.'
            name = "::"
        sys.memcopy(name, buffer + 1, length)
        @(buffer) = length
    }

    sub named(str name) {
        ; -- an empty parameter block with the name in it
        macos.clear_pb()
        pascal(name, &name1)
        pokel(&macos.pb + 18, &name1)
    }

    sub failed(word code) {
        internal_ok = false
        mac_error = code
    }

    sub done(word code) -> bool {
        internal_ok = code == 0
        if code != 0
            mac_error = code
        return internal_ok
    }

    sub catalog(str name) -> word {
        ; -- what the catalog knows of a file or folder; macos.pb has it then: the folder
        ;    bit (16) in the byte at 30, a file's length at 54, a folder's number at 48
        named(name)
        return macos.hfs_call(macos.H_GETCATINFO)
    }

    sub open_fork(str name, ubyte permission) -> long {
        ; -- the file's reference number, or the error
        named(name)
        macos.pb[13] = permission
        word code = macos.file_call(macos.F_OPEN)
        if code != 0
            return code
        return macos.pb[12]
    }

    sub close_fork(uword file) {
        macos.clear_pb()
        macos.pb[12] = file
        void macos.file_call(macos.F_CLOSE)
        macos.clear_pb()
        void macos.file_call(macos.F_FLUSHVOL)
    }

    sub transfer(ubyte function, uword file, pointer buffer, long count) -> long {
        ; -- read or write: how many bytes it was, or the error (the file's end is none)
        macos.clear_pb()
        macos.pb[12] = file
        pokel(&macos.pb + 32, buffer)
        pokel(&macos.pb + 36, count)
        word code = macos.file_call(function)
        if code != 0 and code != ERR_EOF
            return code
        return peekl(&macos.pb + 40)
    }

    sub position(uword file) -> long {
        macos.clear_pb()
        macos.pb[12] = file
        void macos.file_call(macos.F_GETFPOS)
        return peekl(&macos.pb + 46)
    }

    sub fork_size(uword file) -> long {
        macos.clear_pb()
        macos.pb[12] = file
        void macos.file_call(macos.F_GETEOF)
        return peekl(&macos.pb + 28)
    }

    ; ----- the directory -----

    sub directory() -> bool {
        ; -- print the names in the current folder, one on a line; a folder's name has a colon after it
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
                    txt.chrout(':')
                txt.nl()
            }
        }
        lf_end_list()
        internal_ok = true
        return true
    }

    sub diskname() -> str {
        ; -- the name of the disk that the current folder is on
        macos.clear_pb()
        name1[0] = 0
        pokel(&macos.pb + 18, &name1)
        void macos.file_call(macos.F_GETVOL)
        unpascal(&name1, path)
        return path
    }

    sub unpascal(pointer name, pointer text) {
        ubyte length = @(name)
        sys.memcopy(name + 1, text, length)
        @(text + length) = 0
    }

    ; the names of a folder, one at a time: lf_start_list(), then lf_next_entry() for as long as it is true,
    ; each time with the entry in list_filename, list_filetype ("dir" or "prg"), list_filesize and list_blocks
    ; (the size in blocks of 256 bytes, rounded up), then lf_end_list().
    str list_filename = "?" * 31
    str list_filetype = "???"
    long list_filesize = 0
    uword list_blocks = 0
    bool list_more = false
    uword list_index = 0
    str list_pattern = "?" * 31

    sub lf_start_list(str pattern_ptr) -> bool {
        ; -- start a list of the current folder's names that fit the pattern ("*.txt": * is any characters,
        ;    ? any one); 0 or an empty pattern is all of them.
        list_pattern[0] = 0
        if pattern_ptr != 0 and strings.length(pattern_ptr) < 32
            void strings.copy(pattern_ptr, list_pattern)
        list_index = 1
        list_more = true
        internal_ok = true
        return true
    }

    sub lf_next_entry() -> bool {
        ; -- the next entry, or false when there are no more
        while list_more {
            macos.clear_pb()
            name1[0] = 0
            pokel(&macos.pb + 18, &name1)
            macos.pb[14] = list_index
            if macos.hfs_call(macos.H_GETCATINFO) != 0 {
                list_more = false
                return false
            }
            list_index++
            unpascal(&name1, list_filename)
            if msb(macos.pb[15]) & 16 != 0 {
                void strings.copy("dir", list_filetype)
                list_filesize = 0
            }
            else {
                void strings.copy("prg", list_filetype)
                list_filesize = peekl(&macos.pb + 54)
            }
            list_blocks = ((list_filesize + 255) >> 8) as uword
            if list_pattern[0] == 0 or matches(list_filename, list_pattern)
                return true
        }
        return false
    }

    sub lf_end_list() {
        list_more = false
    }

    sub matches(str name, str pattern) -> bool {
        ; -- does the name fit the pattern?  Capitals and small letters are the same.
        ubyte n = 0
        ubyte p = 0
        ubyte star = 255            ; where the last * of the pattern was,
        ubyte resume = 0            ;   and where in the name it is tried from next
        while name[n] != 0 {
            if pattern[p] == '*' {
                star = p
                p++
                resume = n
            }
            else if pattern[p] == '?' or strings.lowerchar(pattern[p]) == strings.lowerchar(name[n]) {
                p++
                n++
            }
            else if star != 255 {
                p = star + 1
                resume++
                n = resume
            }
            else
                return false
        }
        while pattern[p] == '*'
            p++
        return pattern[p] == 0
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
        long file = open_fork(filenameptr, 1)
        if file < 0 {
            failed(file as word)
            return false
        }
        read_file = file as uword
        read_pos = 0
        read_len = 0
        internal_ok = true
        return true
    }

    sub next_byte() -> uword {
        ; -- the next byte of the file that is read, or $ffff at its end
        if read_pos == read_len {
            if read_file == NO_FILE
                return $ffff
            long count = transfer(macos.F_READ, read_file, &read_ahead, AHEAD)
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
        if read_file == NO_FILE
            return 0
        ; (what was read ahead first, then the rest straight into the buffer)
        while read_pos != read_len and actual != num_bytes {
            @(bufferpointer) = read_ahead[read_pos]
            read_pos++
            bufferpointer++
            actual++
        }
        if actual != num_bytes {
            long count = transfer(macos.F_READ, read_file, bufferpointer, num_bytes - actual)
            if count < 0
                failed(count as word)
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
        if read_file != NO_FILE {
            close_fork(read_file)
            read_file = NO_FILE
        }
        read_pos = 0
        read_len = 0
    }

    sub f_seek(long where) -> bool {
        ; -- go to a position, counted from the start, in the file that is open for reading
        if read_file == NO_FILE
            return false
        read_pos = 0
        read_len = 0
        macos.clear_pb()
        macos.pb[12] = read_file
        macos.pb[22] = 1                    ; from the start
        pokel(&macos.pb + 46, where)
        return macos.file_call(macos.F_SETFPOS) == 0
    }

    sub f_tell() -> long, long {
        ; -- the position in the file that is open for reading, and the file's size
        if read_file == NO_FILE
            return 0, 0
        long here = position(read_file) - (read_len - read_pos)
        long size = fork_size(read_file)
        return here, size
    }

    sub f_size() -> long {
        ; -- the size of the file that is open for reading
        if read_file == NO_FILE
            return 0
        return fork_size(read_file)
    }

    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write; an existing file is made empty
        f_close_w()
        named(filenameptr)
        word code = macos.file_call(macos.F_CREATE)
        if code == 0 {
            ; a new file: its type and its creator
            named(filenameptr)
            if macos.file_call(macos.F_GETFINFO) == 0 {
                pokel(&macos.pb + 32, file_type)
                pokel(&macos.pb + 36, file_creator)
                void macos.file_call(macos.F_SETFINFO)
            }
        }
        else if code != ERR_EXISTS {
            failed(code)
            return false
        }
        long file = open_fork(filenameptr, 3)
        if file < 0 {
            failed(file as word)
            return false
        }
        write_file = file as uword
        macos.clear_pb()
        macos.pb[12] = write_file
        void macos.file_call(macos.F_SETEOF)
        internal_ok = true
        return true
    }

    sub f_write(pointer bufferpointer, long num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file; false when not all of them went
        ;    (the disk is full) or no file is open
        if write_file == NO_FILE
            return false
        if num_bytes == 0
            return true
        long count = transfer(macos.F_WRITE, write_file, bufferpointer, num_bytes)
        if count < 0 {
            failed(count as word)
            return false
        }
        internal_ok = count == num_bytes
        return internal_ok
    }

    sub f_close_w() {
        ; -- end an iterative file writing session (close the file).
        if write_file != NO_FILE {
            close_fork(write_file)
            write_file = NO_FILE
        }
    }

    ; ----- folders, status -----

    sub chdir(str name) {
        ; -- make a folder the current one; ".." is the one above
        if catalog(name) != 0 or msb(macos.pb[15]) & 16 == 0 {
            failed(-120)                    ; (the system's "directory not found")
            return
        }
        long number = peekl(&macos.pb + 48)
        macos.clear_pb()
        pokel(&macos.pb + 48, number)
        void done(macos.file_call(macos.F_HSETVOL))
    }

    sub mkdir(str name) {
        named(name)
        void done(macos.hfs_call(macos.H_DIRCREATE))
    }

    sub rmdir(str name) {
        ; -- remove a folder, which must be empty
        named(name)
        void done(macos.file_call(macos.F_DELETE))
    }

    sub curdir() -> str {
        ; -- the current folder, as "Disk:Folder:Folder"
        macos.clear_pb()
        void macos.file_call(macos.F_HGETVOL)
        long number = peekl(&macos.pb + 48)
        ubyte at = 255
        path[255] = 0
        ; from the folder up to the disk, whose number is 2 and whose parent's is 1
        while number > 1 {
            macos.clear_pb()
            name1[0] = 0
            pokel(&macos.pb + 18, &name1)
            macos.pb[14] = $ffff            ; the folder with this number
            pokel(&macos.pb + 48, number)
            if macos.hfs_call(macos.H_GETCATINFO) != 0
                break
            number = peekl(&macos.pb + 100)
            ubyte length = name1[0]
            if at < length + 2
                break
            if at != 255 {
                at--
                path[at] = ':'
            }
            at -= length
            sys.memcopy(&name1 + 1, &path + at, length)
        }
        return &path + at
    }

    sub status() -> str {
        ; -- a text for whether the last operation went well
        if internal_ok
            return "ok"
        return "error"
    }

    sub status_code() -> ubyte {
        ; -- 0, or the File Manager's code of the error without its sign (43 file not found, 34 disk full,
        ;    47 file busy, 48 the name exists, 120 folder not found ...; 255 when there was none)
        if internal_ok
            return 0
        if mac_error == 0
            return 255
        return (-mac_error) as ubyte
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
        named(filenameptr)
        void done(macos.file_call(macos.F_DELETE))
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file or a folder.  It fails when the new name exists.
        named(oldfileptr)
        pascal(newfileptr, &name2)
        pokel(&macos.pb + 28, &name2)
        void done(macos.file_call(macos.F_RENAME))
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file (or folder) exists, otherwise false
        return catalog(filename) == 0
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
