; File I/O routines for the Color Computer with Disk Extended Color BASIC (the coco2
; and coco3 targets of p8p8).
;
; The files are Disk BASIC's (RS-DOS): 35 tracks of 18 sectors of 256 bytes, the
; directory on track 17, a file a chain of granules of 9 sectors in the table in that
; track's sector 2.  This module reads and writes the directory and the table itself;
; of the ROM it calls one routine only, DSKCON (through its vector at $c004), which
; reads or writes a sector.  So it does not depend on where a Disk BASIC version has
; its file routines.
;
; - A name is 8 characters, a dot (or a slash, as BASIC writes it) and 3, taken as
;   capitals, with a drive after it at will ("NAME.EXT:1"); without one the drive is
;   BASIC's default drive.  There are no wildcards.
; - A file's length in bytes is kept exactly.
; - A file that is written is a data file, as BASIC's OPEN "O" makes one; what save()
;   and save_raw() write is marked as binary.
; - Disk BASIC keeps a copy of a disk's table in memory while it has files open on it.
;   A program started with EXEC from the prompt has none open, and BASIC reads the
;   table again after it.
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

    const uword SECTOR = 256
    const ubyte DIRECTORY_TRACK = 17
    const ubyte TABLE_SECTOR = 2            ; of the directory track: the granules' chains
    const ubyte FIRST_ENTRY_SECTOR = 3      ; the directory's entries: sectors 3 to 11, 8 in each
    const ubyte LAST_ENTRY_SECTOR = 11
    const ubyte GRANULES = 68
    const ubyte GRANULE_SECTORS = 9
    const ubyte FREE = $ff                  ; in the table: a granule that no file has
    const ubyte LAST = $c0                  ; in the table: a file's last granule, plus its sectors in use

    ; DSKCON's parameters
    &ubyte dcopc = $00ea                    ; 2 read, 3 write
    &ubyte dcdrv = $00eb
    &ubyte dctrk = $00ec
    &ubyte dsec = $00ed
    &uword dcbpt = $00ee                    ; where the sector's bytes are
    &ubyte dcsta = $00f0                    ; 0: it went well
    &ubyte default_drive = $095a            ; Disk BASIC's default drive

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()

    ubyte[256] read_sector
    ubyte[256] write_sector
    ubyte[256] other_sector     ; a sector of the directory
    ubyte[256] read_table
    ubyte[256] write_table
    ubyte[11] wanted            ; a name as the directory has it: 8 and 3, filled with blanks

    bool reading = false
    ubyte read_drive
    ubyte read_granule          ; where the next sector is read from
    ubyte read_index            ; which of the granule's sectors
    long read_left              ; bytes of the file that are not in read_sector yet
    long read_size
    uword read_at = SECTOR      ; the next byte of read_sector
    uword read_valid = SECTOR   ; how many bytes of read_sector are the file's

    bool writing = false
    bool write_binary = false   ; the file is marked as binary (save, save_raw)
    ubyte write_drive
    ubyte write_first           ; the file's first granule, or FREE when it has none yet
    ubyte write_granule         ; the granule that is written to
    ubyte write_index           ; the sectors of it that are written
    uword write_at = 0          ; the bytes in write_sector
    ubyte[11] write_name

    asmsub dskcon() -> ubyte @A {
        ; -- Disk BASIC's sector routine, with what the bytes from $ea on say; it keeps the registers
        %asm {{
            jsr  [$c004]
            lda  $f0
            rts
        }}
    }

    sub have_disk() -> bool {
        ; -- is Disk BASIC there?  (its ROM begins with "DK")
        return @($c000) == 'D' and @($c001) == 'K'
    }

    sub sector_io(ubyte operation, ubyte drive, ubyte track, ubyte sector, uword buffer) -> bool {
        if not have_disk()
            return false
        dcopc = operation
        dcdrv = drive
        dctrk = track
        dsec = sector
        dcbpt = buffer
        return dskcon() == 0
    }

    sub granule_io(ubyte operation, ubyte drive, ubyte granule, ubyte index, uword buffer) -> bool {
        ; -- a sector of a granule: two granules to a track, and the directory's track between them
        ubyte track = granule >> 1
        if track >= DIRECTORY_TRACK
            track++
        ubyte sector = index + 1
        if granule & 1 != 0
            sector += GRANULE_SECTORS
        return sector_io(operation, drive, track, sector, buffer)
    }

    sub set_name(str name) -> ubyte {
        ; -- the name into "wanted" as the directory has it; returns the drive
        ubyte drive = default_drive
        ubyte k
        for k in 0 to 10
            wanted[k] = ' '
        ubyte at = 0
        bool extension = false
        k = 0
        while name[k] != 0 {
            ubyte c = name[k]
            if c == ':' {
                if name[k + 1] >= '0' and name[k + 1] <= '3'
                    drive = name[k + 1] - '0'
                break
            }
            if c == '.' or c == '/' {
                extension = true
                at = 8
            }
            else {
                if c >= 'a' and c <= 'z'
                    c -= 32
                ; (the name's ninth character and on are left out, and the extension's fourth)
                if (extension and at < 11) or (not extension and at < 8) {
                    wanted[at] = c
                    at++
                }
            }
            k++
        }
        return drive
    }

    ubyte entry_sector          ; where find_entry and free_entry found one: the sector (it is in other_sector)
    ubyte entry_at              ; and its place there

    sub find_entry(ubyte drive) -> bool {
        ; -- the directory entry of the name in "wanted"
        ubyte sector
        for sector in FIRST_ENTRY_SECTOR to LAST_ENTRY_SECTOR {
            if not sector_io(2, drive, DIRECTORY_TRACK, sector, &other_sector) {
                internal_ok = false
                return false
            }
            ubyte at = 0
            repeat 8 {
                if other_sector[at] == $ff
                    return false            ; (no entries from here on)
                if other_sector[at] != 0 {
                    ubyte k = 0
                    while k < 11 and other_sector[at + k] == wanted[k]
                        k++
                    if k == 11 {
                        entry_sector = sector
                        entry_at = at
                        return true
                    }
                }
                at += 32
            }
        }
        return false
    }

    sub free_entry(ubyte drive) -> bool {
        ; -- a directory entry that no file has
        ubyte sector
        for sector in FIRST_ENTRY_SECTOR to LAST_ENTRY_SECTOR {
            if not sector_io(2, drive, DIRECTORY_TRACK, sector, &other_sector)
                return false
            ubyte at = 0
            repeat 8 {
                if other_sector[at] == $ff or other_sector[at] == 0 {
                    entry_sector = sector
                    entry_at = at
                    return true
                }
                at += 32
            }
        }
        return false
    }

    sub free_chain(^^ubyte table, ubyte granule) {
        ; -- the granules of a file are no file's any more
        ubyte steps = 0
        while granule < GRANULES and steps < GRANULES {
            ubyte next = table[granule]
            table[granule] = FREE
            granule = next
            steps++
        }
    }


    ; ----- the directory -----

    sub directory() -> bool {
        ; -- prints the names of the files on the default drive, one on a line
        ubyte sector
        ubyte k
        for sector in FIRST_ENTRY_SECTOR to LAST_ENTRY_SECTOR {
            if not sector_io(2, default_drive, DIRECTORY_TRACK, sector, &other_sector) {
                internal_ok = false
                return false
            }
            ubyte at = 0
            repeat 8 {
                if other_sector[at] == $ff {
                    internal_ok = true
                    return true
                }
                if other_sector[at] != 0 {
                    for k in 0 to 7 {
                        if other_sector[at + k] != ' '
                            txt.chrout(other_sector[at + k])
                    }
                    if other_sector[at + 8] != ' ' {
                        txt.chrout('.')
                        for k in 8 to 10 {
                            if other_sector[at + k] != ' '
                                txt.chrout(other_sector[at + k])
                        }
                    }
                    txt.nl()
                }
                at += 32
            }
        }
        internal_ok = true
        return true
    }

    sub directory_dirs() -> bool {
        ; -- a disk has no directories below it: nothing is printed
        return true
    }

    sub directory_files() -> bool {
        return directory()
    }

    sub diskname() -> str {
        ; -- a disk has no name
        return ""
    }


    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read, f_read_all and f_readline
        ;    note: only a single file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is successfully opened and readable.
        f_close()
        read_drive = set_name(filenameptr)
        internal_ok = find_entry(read_drive)
        if not internal_ok
            return false
        ubyte first = other_sector[entry_at + 13]
        uword last_bytes = mkword(other_sector[entry_at + 14], other_sector[entry_at + 15])
        if not sector_io(2, read_drive, DIRECTORY_TRACK, TABLE_SECTOR, &read_table) {
            internal_ok = false
            return false
        }
        ; its length: whole granules, then the sectors of the last one, the last of
        ; which has last_bytes
        read_size = 0
        ubyte granule = first
        ubyte steps = 0
        while granule < GRANULES and steps < GRANULES {
            ubyte next = read_table[granule]
            if next >= LAST {
                ubyte sectors = next & 15
                if sectors != 0
                    read_size += ((sectors - 1) as long) * SECTOR + last_bytes
                break
            }
            read_size += (GRANULE_SECTORS as long) * SECTOR
            granule = next
            steps++
        }
        read_left = read_size
        read_granule = first
        read_index = 0
        read_at = SECTOR
        read_valid = SECTOR
        reading = true
        return true
    }

    sub next_sector() -> bool {
        ; -- the next sector of the file that is read; false at its end
        if not reading or read_left == 0
            return false
        if read_granule >= GRANULES or not granule_io(2, read_drive, read_granule, read_index, &read_sector) {
            internal_ok = false
            read_left = 0
            return false
        }
        read_valid = SECTOR
        if read_left < SECTOR
            read_valid = read_left as uword
        read_left -= read_valid
        read_at = 0
        read_index++
        if read_index == GRANULE_SECTORS {
            read_index = 0
            read_granule = read_table[read_granule]
        }
        return true
    }

    sub f_read(pointer bufferpointer, pointer num_bytes) -> pointer {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read.
        pointer actual = 0
        while actual != num_bytes {
            if read_at == read_valid {
                if not next_sector()
                    return actual
            }
            uword part = read_valid - read_at
            if part > num_bytes - actual
                part = num_bytes - actual
            sys.memcopy(&read_sector + read_at, bufferpointer, part)
            bufferpointer += part
            actual += part
            read_at += part
        }
        return actual
    }

    sub f_read_all(pointer bufferpointer) -> pointer {
        ; -- read the full rest of the file, returns number of bytes read.
        ;    Usually you will just be using load() / load_raw() to read entire files!
        pointer actual = 0
        repeat {
            if read_at == read_valid {
                if not next_sector()
                    return actual
            }
            uword part = read_valid - read_at
            sys.memcopy(&read_sector + read_at, bufferpointer, part)
            bufferpointer += part
            actual += part
            read_at = read_valid
        }
    }

    sub f_readline(pointer bufptr) -> ubyte, ubyte {
        ; Routine to read text lines from a text file.
        ; Reads characters from the input file UNTIL a return or newline character, or 0 byte, or the end of the file.
        ; A return character with a newline after it is one end.  (Disk BASIC ends a line with a return character.)
        ; The line read will be 0-terminated in the buffer (and not contain the end of line character).
        ; A line longer than 255 characters continues in the next call, so the buffer needs room for 256 bytes.
        ; Returns the length of the line (an empty line is okay and is length 0!), and a status byte:
        ; 0 when the line ended, $40 when the file ended instead, or there was an error, or no file was open.
        ubyte size = 0
        ubyte char
        repeat {
            if read_at == read_valid {
                if not next_sector() {
                    @(bufptr) = 0
                    return size, $40
                }
            }
            char = read_sector[read_at]
            read_at++
            if char == '\r' {
                ; (the newline that follows belongs to it)
                if read_at == read_valid
                    void next_sector()
                if read_at != read_valid and read_sector[read_at] == '\n'
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
        ; -- end an iterative file loading session.
        ;    it is safe to call this multiple times, or when no file is open for reading.
        reading = false
        read_left = 0
        read_at = SECTOR
        read_valid = SECTOR
    }

    sub f_seek(long position) -> bool {
        ; -- not there yet
        return false
    }

    sub f_tell() -> long, long {
        ; -- the position in the file that is read, and its size
        if not reading
            return 0, 0
        return read_size - read_left - (read_valid - read_at), read_size
    }

    sub f_size() -> long {
        if not reading
            return 0
        return read_size
    }


    ; ----- iterative file writing functions -----

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write; a file of that name is replaced
        ;    Returns true if the file is successfully created.
        f_close_w()
        write_binary = false
        return open_w(filenameptr)
    }

    sub open_w(str filenameptr) -> bool {
        write_drive = set_name(filenameptr)
        sys.memcopy(&wanted, &write_name, 11)
        internal_ok = sector_io(2, write_drive, DIRECTORY_TRACK, TABLE_SECTOR, &write_table)
        if not internal_ok
            return false
        ; (a file of that name goes: its granules, and its entry)
        if find_entry(write_drive) {
            free_chain(&write_table, other_sector[entry_at + 13])
            other_sector[entry_at] = 0
            if not sector_io(3, write_drive, DIRECTORY_TRACK, entry_sector, &other_sector)
                    or not sector_io(3, write_drive, DIRECTORY_TRACK, TABLE_SECTOR, &write_table) {
                internal_ok = false
                return false
            }
        }
        write_first = FREE
        write_granule = FREE
        write_index = 0
        write_at = 0
        writing = true
        internal_ok = true
        return true
    }

    sub new_granule() -> bool {
        ; -- a granule that no file has becomes the next one of the file that is written
        ubyte granule = 0
        while granule < GRANULES and write_table[granule] != FREE
            granule++
        if granule == GRANULES
            return false                    ; (the disk is full)
        write_table[granule] = LAST
        if write_first == FREE
            write_first = granule
        else
            write_table[write_granule] = granule
        write_granule = granule
        write_index = 0
        return true
    }

    sub write_out() -> bool {
        ; -- the sector that was filled (or the file's last, partly) goes to the disk
        if write_granule == FREE or write_index == GRANULE_SECTORS {
            if not new_granule()
                return false
        }
        if not granule_io(3, write_drive, write_granule, write_index, &write_sector)
            return false
        write_index++
        write_at = 0
        return true
    }

    sub f_write(pointer bufferpointer, pointer num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        if not writing
            return false
        while num_bytes != 0 {
            uword part = SECTOR - write_at
            if part > num_bytes
                part = num_bytes
            sys.memcopy(bufferpointer, &write_sector + write_at, part)
            bufferpointer += part
            num_bytes -= part
            write_at += part
            if write_at == SECTOR {
                if not write_out() {
                    internal_ok = false
                    return false
                }
            }
        }
        return true
    }

    sub f_close_w() {
        ; -- end an iterative file writing session: the last sector, the table and the
        ;    file's entry in the directory are written.
        if not writing
            return
        writing = false
        ; how many bytes of the last sector are the file's
        uword last_bytes = SECTOR
        if write_at != 0 {
            last_bytes = write_at
            if not write_out() {
                internal_ok = false
                return
            }
        }
        else if write_granule == FREE {
            ; (an empty file has a granule too, with no sector in use)
            last_bytes = 0
            if not new_granule() {
                internal_ok = false
                return
            }
        }
        write_table[write_granule] = LAST + write_index
        if not sector_io(3, write_drive, DIRECTORY_TRACK, TABLE_SECTOR, &write_table) or not free_entry(write_drive) {
            internal_ok = false
            return
        }
        ubyte k
        for k in 0 to 31
            other_sector[entry_at + k] = 0
        for k in 0 to 10
            other_sector[entry_at + k] = write_name[k]
        other_sector[entry_at + 11] = 1         ; a data file
        if not write_binary
            other_sector[entry_at + 12] = $ff   ; of text
        other_sector[entry_at + 13] = write_first
        other_sector[entry_at + 14] = msb(last_bytes)
        other_sector[entry_at + 15] = lsb(last_bytes)
        if not sector_io(3, write_drive, DIRECTORY_TRACK, entry_sector, &other_sector)
            internal_ok = false
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
        ; -- Disk BASIC's default drive: 0 to 3
        return default_drive
    }


    ; ----- whole files -----

    sub save(str filenameptr, pointer start_address, pointer savesize) -> bool {
        ; -- save the memory block in a file, after a 2-byte prg header with the start address
        ;    (its low byte first, as on the other machines).
        ;    An existing file is overwritten. Returns true if successful.
        ubyte[2] header
        header[0] = lsb(start_address)
        header[1] = msb(start_address)
        f_close_w()
        write_binary = true
        if not open_w(filenameptr)
            return false
        internal_ok = f_write(&header, 2) and f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; like save() but omits the 2 byte prg header.
    sub save_raw(str filenameptr, pointer start_address, pointer savesize) -> bool {
        f_close_w()
        write_binary = true
        if not open_w(filenameptr)
            return false
        internal_ok = f_write(start_address, savesize)
        f_close_w()
        return internal_ok
    }

    ; Load the given file in memory, skipping the 2-byte prg header in the file: at the address given,
    ; or with 0 at the address that the header says.
    ; Returns the end load address+1 if successful or 0 if a load error occurred.
    sub load(str filenameptr, pointer address_override) -> pointer {
        ubyte[2] header
        if not f_open(filenameptr)
            return 0
        if f_read(&header, 2) != 2 {
            f_close()
            internal_ok = false
            return 0
        }
        if address_override == 0
            address_override = mkword(header[1], header[0])
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
        ubyte drive = set_name(filenameptr)
        internal_ok = find_entry(drive)
        if not internal_ok
            return
        ubyte first = other_sector[entry_at + 13]
        other_sector[entry_at] = 0
        if not sector_io(3, drive, DIRECTORY_TRACK, entry_sector, &other_sector)
                or not sector_io(2, drive, DIRECTORY_TRACK, TABLE_SECTOR, &other_sector) {
            internal_ok = false
            return
        }
        free_chain(&other_sector, first)
        internal_ok = sector_io(3, drive, DIRECTORY_TRACK, TABLE_SECTOR, &other_sector)
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file on the drive (the old name's drive)
        ubyte[11] new_name
        void set_name(newfileptr)
        sys.memcopy(&wanted, &new_name, 11)
        ubyte drive = set_name(oldfileptr)
        internal_ok = find_entry(drive)
        if not internal_ok
            return
        ubyte k
        for k in 0 to 10
            other_sector[entry_at + k] = new_name[k]
        internal_ok = sector_io(3, drive, DIRECTORY_TRACK, entry_sector, &other_sector)
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists on the disk, otherwise false
        ubyte drive = set_name(filename)
        return find_entry(drive)
    }

    sub get_loadaddress(str filename) -> uword {
        ; -- the address in the 2-byte header of a file that save() wrote; 0 when it cannot be read
        ubyte[2] header
        uword address = 0
        if f_open(filename) {
            if f_read(&header, 2) == 2
                address = mkword(header[1], header[0])
            f_close()
        }
        return address
    }
}
