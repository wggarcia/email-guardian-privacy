class UsuarioEmail {
  String email;
  String provedor; // "gmail", "outlook", "yahoo", "imap"
  String tokenOauth; // opcional
  String senha; // opcional
  String servidorImap; // opcional

  UsuarioEmail({
    required this.email,
    required this.provedor,
    this.tokenOauth = '',
    this.senha = '',
    this.servidorImap = '',
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'provedor': provedor,
        'token_oauth': tokenOauth,
        'senha': senha,
        'servidor_imap': servidorImap,
      };
}