/*
 * facade-stub.h — runtime header for the mail-send facade.
 *
 * Sender drives the runtime's built-in TcpClient + amalgame-tls and
 * signs via amalgame-mail-dkim. Required only by amc's [stdlib].header;
 * the user binary's #include is a no-op.
 */
