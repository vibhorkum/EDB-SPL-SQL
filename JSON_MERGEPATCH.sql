CREATE OR REPLACE FUNCTION json_mergepatch(target_expr JSONB, patch_expr JSONB)
RETURNS JSONB
LANGUAGE SQL
IMMUTABLE
AS $function$
  /* Author: Vibhor Kumar
     Email id: vibhor.aim@gmail.com
     Developed On: March 25th, 2024
     Function: json_mergepatch(jsonb, jsonb)
     Description: Merges two JSONB documents according to RFC 7396.
     Arguments:
       target_expr: The target JSONB document.
       patch_expr: The patch JSONB document.
     Returns:
      The merged JSONB document.
  */
  SELECT 
    CASE
      WHEN target_expr IS NULL OR patch_expr IS NULL THEN NULL  -- Handle NULL inputs
      ELSE jsonb_strip_nulls(
              replace(
                (target_expr || patch_expr)::TEXT, 
                '""', 'null'  -- Replace empty strings with nulls for compatibility
              )::JSONB
           )
    END;
$function$;