-- csv.lua (internal file)

do

local ffi = require 'ffi'

ffi.cdef[[
    typedef void (*csv_emit_row_t)(void *ctx);
    typedef void (*csv_emit_field_t)(void *ctx, const char *field, const char *end);

    struct csv
    {
        void *emit_ctx;
        csv_emit_row_t emit_row;
        csv_emit_field_t emit_field;
        char csv_delim;
        char csv_quote;

        int csv_invalid;
        int csv_ending_spaces;

        void *(*csv_realloc)(void*, size_t);

        int state;
        char *buf;
        char *bufp;
        size_t buf_len;
    };
    void csv_create(struct csv *csv);
    void csv_destroy(struct csv *csv);
    void csv_setopt(struct csv *csv, int opt, ...);
    struct csv_iterator {
        struct csv *csv;
        const char *buf_begin;
        const char *buf_end;
        const char *field;
        size_t field_len;
    };
    typedef struct csv csv_t;
    typedef struct csv_iterator csv_iterator_t;
    void csv_iter_create(struct csv_iterator *it, struct csv *csv);
    int csv_next(struct csv_iterator *);
    void csv_feed(struct csv_iterator *, const char *);
    int csv_escape_field(struct csv *, const char *, char *);
    enum {
        CSV_IT_OK,
        CSV_IT_EOL,
        CSV_IT_NEEDMORE,
        CSV_IT_EOF,
        CSV_IT_ERROR
    };
]]

csv = {
load = function(readable, csv_chunk_size)
    csv_chunk_size = csv_chunk_size or 4096
    if type(readable.read) ~= "function" then
       error("Usage: load(object with read method)")
    end
    local log = require('log')

    local it = ffi.new('csv_iterator_t[1]')
    local csv = ffi.new('csv_t[1]')
    ffi.C.csv_create(csv)
    ffi.C.csv_iter_create(it, csv)
    local st = ffi.C.csv_next(it)
    local tup = {}
    local result = {}
    while st ~= ffi.C.CSV_IT_EOF do
        if st == ffi.C.CSV_IT_NEEDMORE then
            ffi.C.csv_feed(it, readable:read(csv_chunk_size))
        elseif st == ffi.C.CSV_IT_EOL then
            table.insert(result, tup)
            tup = {}
        elseif st == ffi.C.CSV_IT_OK then
            table.insert(tup, ffi.string(it[0].field, it[0].field_len))
        elseif st == ffi.C.CSV_IT_ERROR then
            log.warn("CSV file has errors")
        elseif st == ffi.C.CSV_IT_EOF then
            break
        end
        st = ffi.C.csv_next(it)
    end

    return result
end
,
dump = function(writable, t)
    if type(writable.write) ~= "function" or type(t) ~= "table" then
       error("Usage: dump(writable, table)")
    end
    local csv = ffi.new('csv_t[1]')
    ffi.C.csv_create(csv)
    local bufsz = 256
    --local buf = ffi.new('char[?]', bufsz)
    local buf = csv[0].csv_realloc(ffi.cast(ffi.typeof('void *'), 0), bufsz)
    for k, line in pairs(t) do
        first = true
        for k2, field in pairs(line) do
            strf = tostring(field)
            if (strf:len() + 1) * 2 > bufsz then
                bufsz = (strf:len() + 1) * 2
                buf = csv[0].csv_realloc(buf, bufsz)
            end
            local len = ffi.C.csv_escape_field(csv, strf, buf)
            if first then
                first = false
            else
                writable:write(',')
            end              
            writable:write(ffi.string(buf, len))
        end
        writable:write('\n')  
    end
    csv[0].csv_realloc(buf, 0)
end

}
return csv
end
