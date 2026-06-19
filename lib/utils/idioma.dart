class Idioma {
  final String codigo;

  Idioma(this.codigo);

  bool get isPT => codigo.startsWith("pt");
  bool get isEN => codigo.startsWith("en");

  String get titulo => "Email Guardian";

  String get limpar => isPT ? "Limpar" : "Clean";
  String get ia => isPT ? "IA" : "AI";
  String get parar => isPT ? "Parar" : "Stop";

  String get protecaoOn => isPT ? "Proteção ativa" : "Protection active";
  String get sistemaPronto => isPT ? "Sistema pronto" : "System ready";

  String get risco => isPT ? "Risco" : "Risk";
  String get promocoes => isPT ? "Promoções" : "Promotions";

  String get removerSelecionados =>
      isPT ? "Remover Selecionados" : "Remove Selected";
}