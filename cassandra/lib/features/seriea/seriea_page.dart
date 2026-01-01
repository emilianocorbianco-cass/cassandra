import 'package:flutter/material.dart';
import '../../app/widgets/cassandra_page.dart';

class SerieAPage extends StatelessWidget {
  const SerieAPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CassandraPage(
      title: 'Serie A',
      child: Center(child: Text('Risultati e classifica Serie A')),
    );
  }
}
