CREATE OR replace PROCEDURE Send_mail_clob (p_to          IN VARCHAR2,
                                            p_from        IN VARCHAR2,
                                            p_subject     IN VARCHAR2,
                                            p_text_msg    IN VARCHAR2 DEFAULT NULL,
                                            p_attach_name IN VARCHAR2 DEFAULT NULL,
                                            p_attach_mime IN VARCHAR2 DEFAULT NULL,
                                            p_attach_clob IN CLOB DEFAULT NULL,
                                            p_smtp_host   IN VARCHAR2,
                                            p_smtp_port   IN INTEGER DEFAULT 25)
AS
    /* Author: Vibhor Kumar
       Email id: vibhor.aim@gmail.com
       Developed On: April 9th, 2024
       Description: This procedures takes argument information and sends Text attacchement
                    
    */

  l_mail_conn UTL_SMTP.connection;
  l_boundary  VARCHAR2 (50) := '----=abc1234321cba=';
  l_step      PLS_INTEGER := 12000;
-- make sure you set a multiple of 3 not higher than 24573
BEGIN
    l_mail_conn := UTL_SMTP.Open_connection (p_smtp_host, p_smtp_port);

    UTL_SMTP.Helo (l_mail_conn, p_smtp_host);

    UTL_SMTP.Mail (l_mail_conn, p_from);

    UTL_SMTP.Rcpt (l_mail_conn, p_to);

    UTL_SMTP.Open_data (l_mail_conn);

    UTL_SMTP.Write_data (l_mail_conn, 'Date: '
                                      ||
    To_char(SYSDATE, 'DD-MON-YYYY HH24:MI:SS')
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn, 'To: '
                                      || p_to
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn, 'From: '
                                      || p_from
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn, 'Subject: '
                                      || p_subject
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn, 'Reply-To: '
                                      || p_from
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn, 'MIME-Version: 1.0'
                                      || utl_tcp.crlf);

    UTL_SMTP.Write_data (l_mail_conn,
    'Content-Type: multipart/mixed; boundary="'
    || l_boundary
    || '"'
    || utl_tcp.crlf
    || utl_tcp.crlf);

    IF p_text_msg IS NOT NULL THEN
      UTL_SMTP.Write_data (l_mail_conn, '--'
                                        || l_boundary
                                        || utl_tcp.crlf);

      UTL_SMTP.Write_data (l_mail_conn,
      'Content-Type: text/plain; charset="iso-8859-1"'
      || utl_tcp.crlf
      || utl_tcp.crlf);

      UTL_SMTP.Write_data (l_mail_conn, p_text_msg);

      UTL_SMTP.Write_data (l_mail_conn, utl_tcp.crlf
                                        || utl_tcp.crlf);
    END IF;

    IF p_attach_name IS NOT NULL THEN
      UTL_SMTP.Write_data (l_mail_conn, '--'
                                        || l_boundary
                                        || utl_tcp.crlf);

      UTL_SMTP.Write_data (l_mail_conn, 'Content-Type: '
                                        || p_attach_mime
                                        || '; name="'
                                        || p_attach_name
                                        || '"'
                                        || utl_tcp.crlf);

      UTL_SMTP.Write_data (l_mail_conn,
      'Content-Disposition: attachment; filename="'
      || p_attach_name
      || '"'
      || utl_tcp.crlf
      || utl_tcp.crlf);

      FOR i IN 0..Trunc((dbms_lob.Getlength (p_attach_clob) - 1) / l_step) LOOP
          UTL_SMTP.Write_data (l_mail_conn,
          dbms_lob.Substr(p_attach_clob, l_step, i
          *
          l_step + 1));
      END LOOP;

      UTL_SMTP.Write_data (l_mail_conn, utl_tcp.crlf
                                        || utl_tcp.crlf);
    END IF;

    UTL_SMTP.Write_data (l_mail_conn, '--'
                                      || l_boundary
                                      || '--'
                                      || utl_tcp.crlf);

    UTL_SMTP.Close_data (l_mail_conn);

    UTL_SMTP.Quit (l_mail_conn);
END; 

/*
 Example of usage
*/

DECLARE
  l_clob CLOB := 'This is a sample attachement data send it as attachement!';
BEGIN
  send_mail_clob(p_to          => 'xxxx@edb.com',
            p_from        => 'xxxx@gmail.com',
            p_subject     => 'Rocky Linux 8 Message',
            p_text_msg    => 'Please find attached file',
            p_attach_name => 'test.txt',
            p_attach_mime => 'text/plain',
            p_attach_clob => l_clob,
            p_smtp_host   => '127.0.0.1',
            p_smtp_port => 1587);
END;

