DROP FUNCTION IF EXISTS show_function_signature(oid);
DROP FUNCTION IF EXISTS get_raw_dependency_tree_by_oid;
DROP FUNCTION IF EXISTS get_raw_dependency_tree;
DROP FUNCTION IF EXISTS get_dependency_tree;

CREATE OR REPLACE FUNCTION show_function_signature(oid)
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
        pr.oid = $1 AND ns.nspparent = 0
    UNION
    SELECT
        pg_catalog.format('%I.%I.%I(%s)', ns.nspname, 
        pack.nspname, pr.proname, edb_get_function_arguments (pr.oid))
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

CREATE OR REPLACE FUNCTION get_raw_dependency_tree_by_oid(
                                                 proc_oid oid,
                                                 depth_level integer DEFAULT 20063, 
                                                 ON_COMMIT text DEFAULT 'DROP'
                                                 ) 
RETURN TABLE (
    proc_name oid,
    calling_proc oid,
    procedure_type text,
    nested_level integer
)
AS $function$
/* Author: Vibhor Kumar
 Email id: vibhor.aim@gmail.com
 Developed On: March 29th, 2024
 Description: This function takes function oid and shows the dependency tree in 
 raw format.
 */
DECLARE
    level INTEGER := 0;
    dep_insert_sql text;
    rec RECORD;
    for_loop_sql text;
    schema_name text;
    validate_sql text;
    is_edbspl_function integer;
    found_count integer := 0;
    temp_tbl_name text := 'temp_dep_tree';
    return_query text := pg_catalog.format('SELECT * FROM %I', temp_tbl_name);
    temp_tbl_sql text := 'CREATE TEMP TABLE IF NOT EXISTS temp_dep_tree(proc_name OID,'
                         || ' calling_proc OID, procedure_type TEXT,' 
                         || ' nested_level INTEGER) ON COMMIT ' || ON_COMMIT;
BEGIN
    /* 
     DROP  and CREATE temp tables
     */
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || temp_tbl_name;
    EXECUTE IMMEDIATE temp_tbl_sql;

    /*
     Verify if procedure/function is using EDBSPL or not
     */
    SELECT
        COUNT(1) INTO is_edbspl_function
    FROM
        pg_catalog.pg_proc pr JOIN pg_catalog.pg_language pl
        ON (pr.prolang = pl.oid)
    WHERE
        pl.lanname = 'edbspl' AND pr.oid = proc_oid;
    IF is_edbspl_function < 1 THEN
        SELECT
            CASE WHEN ns.nspparent != 0 THEN
                ns.nspparent::regnamespace::text || '.'
            ELSE
                ''
            END INTO schema_name
        FROM
            pg_namespace ns
        WHERE
            oid = (
                SELECT
                    pronamespace
                FROM
                    pg_proc WHERE oid = proc_oid);
        RAISE NOTICE '%s%s is not a edbspl function/procedure or deosnt exist',
                      schema_name, proc_oid::regproc::text;
    END IF;

    /*
     Start a loop based on the max depth level provided by the user
     and go over it till we cover all possible procedure or function
     */
    WHILE (level < depth_level)
    LOOP
        IF level = 0 THEN
            /*
             If it's first time execution then only capture level 1
             */
            dep_insert_sql := pg_catalog.format($$ INSERT INTO %I
                SELECT
                    %s, oid, type, %s FROM spl_show_dependency_tb ('%s'::regproc)
                    WHERE
                        type IN ('PROCEDURE', 'FUNCTION') $$, 
                        temp_tbl_name, proc_oid, level, proc_oid);
            EXECUTE IMMEDIATE dep_insert_sql;
            level := level +1;
            RAISE NOTICE 'Level %', level;
        ELSE
            /*
             if it's other than 1st time execution, then go over all function/procedure
             of previous level and capture into the table
             */
            for_loop_sql := pg_catalog.format($$
                SELECT
                    * FROM %I t
                    JOIN pg_catalog.pg_proc pr ON (t.calling_proc = pr.oid)
                    JOIN pg_catalog.pg_language pl ON (pr.prolang = pl.oid)
                    WHERE
                        nested_level = %s
                        AND pl.lanname = 'edbspl' $$, temp_tbl_name, level -1);

            /*
             Use validate_sql to verify if we really need to go further for capturing
             tree. if there is no more rows/functions to travel through, we can stop
             */
            validate_sql := pg_catalog.format($$
                SELECT
                    COUNT(*)
                    FROM %I t
                    JOIN pg_catalog.pg_proc pr ON (t.calling_proc = pr.oid)
                    JOIN pg_catalog.pg_language pl ON (pr.prolang = pl.oid)
                    WHERE
                        nested_level = %s
                        AND pl.lanname = 'edbspl' LIMIT 1$$, temp_tbl_name, level -1);
            EXECUTE IMMEDIATE validate_sql INTO found_count;
            IF found_count = 0 THEN
                level = depth_level;
                EXIT;
            END IF;

            /*
             Go over function/procedure to capture next level of calling procedures
             functions
             */
            FOR rec IN EXECUTE for_loop_sql LOOP
                RAISE NOTICE 'LEVEL % => %', level, rec.calling_proc::regproc;
                dep_insert_sql := pg_catalog.format($$ INSERT INTO %I
                    SELECT
                        %s, oid, type, %s FROM spl_show_dependency_tb ('%s'::regproc)
                        WHERE
                            type IN ('PROCEDURE', 'FUNCTION') $$,
                            temp_tbl_name, rec.calling_proc, level, rec.calling_proc);
                EXECUTE IMMEDIATE dep_insert_sql;
                level := level +1;
            END LOOP;
        END IF;
    END LOOP;
    RETURN QUERY EXECUTE return_query;
END;
$function$;

CREATE OR REPLACE FUNCTION get_raw_dependency_tree (schema_name text, 
                                                    package_name text DEFAULT '', 
                                                    procedure_name text, 
                                                    depth_level integer DEFAULT 20063, 
                                                    ON_COMMIT text DEFAULT 'DROP')
RETURN TABLE (
    function_sr_id bigint,
    main_procedure text,
    proc_name oid,
    calling_proc oid,
    procedure_type text,
    nested_level integer
)
AS $function$
/* Author: Vibhor Kumar
 Email id: vibhor.aim@gmail.com
 Developed On: March 29th, 2024
 Description: This function takes schema, package and procedure names and shows
 shows the dependency tree in raw format.
 */
DECLARE
    rec RECORD;
    is_edbspl_function integer;
    found_count integer := 0;
    current_proc_list oid[];
    pro_rec RECORD;
BEGIN
    IF package_name != '' THEN
        /* 
         Capture oid list of the procedure if the package name is provided.
         */
        SELECT
            array_agg(pr.oid) INTO current_proc_list
        FROM
            pg_catalog.pg_proc pr
            JOIN pg_catalog.pg_namespace pack ON (pr.pronamespace = pack.oid)
            JOIN pg_catalog.pg_namespace ns ON (pack.nspparent = ns.oid)
            JOIN pg_catalog.pg_language pl ON (pr.prolang = pl.oid)
        WHERE
            ns.nspparent = 0
            AND pack.nspparent != 0
            AND pr.proname = procedure_name
            AND pack.nspname = package_name
            AND ns.nspname = schema_name
            AND pl.lanname = 'edbspl';
    ELSE
        /* 
         Capture oid list of the procedure if package name is not provided.
         */
        SELECT
            array_agg(pr.oid) INTO current_proc_list
        FROM
            pg_catalog.pg_proc pr
            JOIN pg_catalog.pg_namespace ns ON (pr.pronamespace = ns.oid)
            JOIN pg_catalog.pg_language pl ON (pr.prolang = pl.oid)
        WHERE
            ns.nspparent = 0
            AND pr.proname = procedure_name
            AND ns.nspname = schema_name
            AND pl.lanname = 'edbspl';
    END IF;
    IF NVL (array_length(current_proc_list, 1), 0) < 1 THEN
        RAISE NOTICE '%s is not a edbspl function', procedure_name;
        RETURN;
    END IF;

    /*
     Start a loop based on the max depth level provided by the user
     and go over it till we cover all possible procedure or function
     */
    FOR pro_rec IN
    SELECT
        rownum, unnest(current_proc_list) AS pro_oid
        LOOP
            FOR rec IN
            SELECT
                *
            FROM
                get_raw_dependency_tree_by_oid (pro_rec.pro_oid, 
                                                depth_level, ON_COMMIT)
                LOOP
                    RETURN NEXT ROW (
                        pro_rec.rownum,
                        show_function_signature(pro_rec.pro_oid),
                        rec.proc_name,
                        rec.calling_proc,
                        rec.procedure_type,
                        rec.nested_level);
                END LOOP;
        END LOOP;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION get_dependency_tree (schema_name text,
                                                package_name text DEFAULT '', 
                                                procedure_name text,
                                                depth_level integer DEFAULT 20063, 
                                                ON_COMMIT text DEFAULT 'DROP')
    RETURNS TABLE (
        function_sr_id bigint,
        main_procedure text,
        caller_procedure text,
        calling_procedure text,
        procedure_type text,
        nested_level integer)
    LANGUAGE SQL
    AS $function$
    /* Author: Vibhor Kumar
     Email id: vibhor.aim@gmail.com
     Developed On: March 29th, 2024
     Description: This function takes schema, package and procedure names and shows
     shows the dependency tree in readable format with arguments
     */
    SELECT
        function_sr_id,
        main_procedure,
        show_function_signature (proc_name) AS caller,
        show_function_signature (calling_proc) AS calling_proc,
        procedure_type,
        nested_level
    FROM
        get_raw_dependency_tree (schema_name, package_name, procedure_name, depth_level, ON_COMMIT);
$function$;


/*
 Calling example
 SELECT * FROM get_dependency_tree(schema_name := 'public', procedure_name := 'test_numeric3', depth_level := 30000);
  SELECT * FROM get_dependency_tree(schema_name := 'public', procedure_name := 'test_procedure2', package_name := 'test_package', depth_level := 30000);
 */
