CREATE OR REPLACE FUNCTION show_function_signature (oid)
    RETURNS text
    LANGUAGE SQL
    AS $function$
    /* Author: Vibhor Kumar
       Email id: vibhor.aim@gmail.com
       Developed On: March 25th, 2024
       Description: This function takes OID of a procedure/function and
                    shows the function signature
    */
    SELECT
        pg_catalog.format('%I.%I(%s)', ns.nspname, pr.proname, 
        pg_catalog.edb_get_function_arguments (pr.oid))
    FROM
        pg_catalog.pg_proc pr
        JOIN pg_catalog.pg_namespace ns ON (ns.oid = pr.pronamespace)
    WHERE
        pr.oid = $1
        AND ns.nspparent = 0
    UNION
    SELECT
        pg_catalog.format('%I.%I.%I(%s)', ns.nspname, pack.nspname, pr.proname, edb_get_function_arguments (pr.oid))
    FROM
        pg_catalog.pg_proc pr
        JOIN pg_catalog.pg_namespace pack ON (pr.pronamespace = pack.oid
                AND pack.nspparent != 0)
        JOIN pg_catalog.pg_namespace ns ON (pack.nspparent = ns.oid)
    WHERE
        ns.nspparent = 0
        AND pack.nspparent != 0
        AND pr.oid = $1
$function$;

CREATE OR REPLACE FUNCTION show_function_oids (text)
    RETURNS oid[]
    LANGUAGE SQL
    AS $function$
    /* Author: Vibhor Kumar
       Email id: vibhor.aim@gmail.com
       Developed On: March 25th, 2024
       Description: This function takes procedure/functionname as 
                    <schema-name>.<procedure/function-name> or 
                    <schema-name>.<package-name>.<procedure/function-name>
                    shares the procedure/function OIDs of matching function/procedure
                    name
    */
    SELECT
        CASE WHEN array_length(arr, 1) = 3 THEN
        (
            SELECT
                pg_catalog.array_agg(pr.oid)
            FROM
                pg_catalog.pg_proc pr
                JOIN pg_catalog.pg_namespace pack ON (pr.pronamespace = pack.oid
                        AND pack.nspparent != 0)
                JOIN pg_catalog.pg_namespace ns ON (pack.nspparent = ns.oid
                        AND ns.nspparent = 0)
            WHERE
                ns.nspname = trim(arr[1])
                AND pack.nspname = trim(arr[2])
                AND pr.proname = trim(arr[3]))
        WHEN array_length(arr, 1) = 2 THEN
        (
            SELECT
                pg_catalog.array_agg(pr.oid)
            FROM
                pg_catalog.pg_proc pr
                JOIN pg_catalog.pg_namespace ns ON (pr.pronamespace = ns.oid)
            WHERE
                ns.nspname = trim(arr[1])
                AND pr.proname = trim(arr[2]))
    ELSE
        (
            SELECT
                pg_catalog.array_agg(pr.oid)
            FROM
                pg_catalog.pg_proc pr
            WHERE
                pr.proname = trim($1))
        END
    FROM
        regexp_split_to_array($1, '\.') foo (arr)
$function$;

CREATE OR REPLACE FUNCTION scan_typecast_errors (schema_name text)
    RETURNS TABLE (
        schema_name name,
        package_name text,
        proname name,
        lineno integer,
        message text,
        called_procedure_name text)
    LANGUAGE SQL
    AS $function$
    /* Author: Vibhor Kumar
       Email id: vibhor.aim@gmail.com
       Developed On: March 25th, 2024
       Description: This function scans all procedures/packages of a given schema
                   and shares the information on possible typecast error issues in 
                   the code with called function name
    */
    SELECT
        ns.nspname AS schema_name,
        NULL::text AS package_name,
        pr.proname AS name,
        perr.lineno,
        perr.message,
        split_part(split_part(message, ' ', 2), '(', 1) AS called_procedure_name
    FROM
        pg_catalog.pg_proc pr
        JOIN pg_catalog.pg_namespace ns ON (pr.pronamespace = ns.oid)
        JOIN pg_catalog.pg_type tp ON (tp.oid = pr.prorettype)
        JOIN LATERAL (
            SELECT
                functionid,
                lineno,
                message,
                sqlstate
            FROM
                spl_check_function_tb (pr.oid::regproc, fatal_errors := FALSE)
            WHERE
                sqlstate = 42883) perr ON TRUE
    WHERE
        ns.oid = pr.pronamespace
        AND pr.pronamespace = ns.oid
        AND pr.prorettype = tp.oid
        AND pr.protype = '1'::"char"
        AND ns.nspparent = 0::oid
        AND tp.typname <> 'trigger'::name
        AND ns.nspname = schema_name
    UNION ALL
    SELECT
        s.nspname AS schema_name,
        pack.nspname AS package_name,
        p.proname AS name,
        perr.lineno,
        perr.message,
        split_part(split_part(message, ' ', 2), '(', 1) AS called_procedure_name
    FROM
        pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace pack ON pack.oid = p.pronamespace
        JOIN pg_catalog.pg_namespace s ON s.oid = pack.nspparent
        JOIN LATERAL (
            SELECT
                functionid,
                lineno,
                message,
                sqlstate
            FROM
                spl_check_function_tb (p.oid::regproc, fatal_errors := FALSE)
            WHERE
                sqlstate = 42883) perr ON TRUE
    WHERE
        p.prorettype <> 'pg_catalog.cstring'::pg_catalog.regtype
        AND (p.proargtypes[0] IS NULL
            OR p.proargtypes[0] <> 'pg_catalog.cstring'::pg_catalog.regtype)
        AND p.prokind <> 'a'
        AND pack.nspparent != 0
        AND pack.nspobjecttype = 0
        AND s.nspname = schema_name
$function$;

/* Sample calling example
SELECT
    *,
    (
        SELECT
            pg_catalog.string_agg(show_function_signature (arr), E'\n')
        FROM
            pg_catalog.unnest(show_function_oids (called_procedure_name)) foo (arr)) AS func_arguments
    FROM
        scan_typecast_errors ('public');
*/
CREATE OR REPLACE FUNCTION scan_package_typecast_errors (schema_name text, package_name text)
    RETURNS TABLE (
        schema_name name,
        package_name text,
        proname name,
        lineno integer,
        message text,
        called_procedure_name text)
    LANGUAGE SQL
    AS $function$
    /* Author: Vibhor Kumar
       Email id: vibhor.aim@gmail.com
       Developed On: March 25th, 2024
       Description: This function scans all procedures/packages of a given schema & 
                   package_name
                   and shares the information on possible typecast error issues in 
                   the code with called function name
    */
    
    SELECT
        s.nspname AS schema_name,
        pack.nspname AS package_name,
        p.proname AS name,
        perr.lineno,
        perr.message,
        split_part(split_part(message, ' ', 2), '(', 1) AS called_procedure_name
    FROM
        pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace pack ON pack.oid = p.pronamespace
        JOIN pg_catalog.pg_namespace s ON s.oid = pack.nspparent
        JOIN LATERAL (
            SELECT
                functionid,
                lineno,
                message,
                sqlstate
            FROM
                spl_check_function_tb (p.oid::regproc, fatal_errors := FALSE)
            WHERE
                sqlstate = 42883) perr ON TRUE
    WHERE
        p.prorettype <> 'pg_catalog.cstring'::pg_catalog.regtype
        AND (p.proargtypes[0] IS NULL
            OR p.proargtypes[0] <> 'pg_catalog.cstring'::pg_catalog.regtype)
        AND p.prokind <> 'a'
        AND pack.nspparent != 0
        AND pack.nspobjecttype = 0
        AND s.nspname = schema_name
        AND pack.nspname = package_name
$function$;

/*
SELECT * 
FROM scan_package_typecast_errors(schema_name:= 'public',
                              package_name := 'test_package');
*/