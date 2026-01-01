import 'package:flutter/material.dart';
import '../../app/widgets/cassandra_page.dart';

class GroupPage extends StatelessWidget {
  const GroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CassandraPage(
      title: 'Il mio gruppo',
      child: Center(child: Text('Classifica gruppo + tap su utente')),
    );
  }
}
