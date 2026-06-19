import 'package:flutter/material.dart';

class CardEmail extends StatelessWidget {
  final Map email;
  CardEmail({required this.email});

  @override
  Widget build(BuildContext context) {
    Color corRisco = email['risco'] ? Colors.red : Colors.green;
    return Card(
      child: ListTile(
        title: Text(email['assunto'] ?? 'Sem Assunto'),
        subtitle: Text(email['remetente'] ?? 'Desconhecido'),
        trailing: Icon(Icons.warning, color: corRisco),
      ),
    );
  }
}