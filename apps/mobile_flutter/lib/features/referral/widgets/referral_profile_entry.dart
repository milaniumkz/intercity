import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ReferralProfileEntry extends StatelessWidget {
  const ReferralProfileEntry({super.key});
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        leading: Icon(Icons.group_add_outlined,
            color: Theme.of(context).colorScheme.primary),
        title: const Text('Реферальная система'),
        subtitle: const Text('Приглашения, доход и налоговый статус'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/referral-account'),
      ));
}
