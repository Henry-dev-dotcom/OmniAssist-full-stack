import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../auth/auth_controller.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'funding_data.dart';

const fundingStatuses = ['not_started','researching','preparing','submitted','awarded','rejected','not_eligible'];
const fundingPriorities = ['high','medium','low'];
String pretty(String value) => value.replaceAll('_', ' ');

class FundingScreen extends ConsumerStatefulWidget {
  const FundingScreen({super.key});
  @override ConsumerState<FundingScreen> createState() => _FundingScreenState();
}
class _FundingScreenState extends ConsumerState<FundingScreen> {
  String _query = '';
  String? _status;
  String? _priority;
  Future<void> _sync() => ref.read(syncControllerProvider.notifier).syncNow();
  List<Rec> get _all => ref.read(recordsProvider('funding_opportunity')).value ?? const [];
  Future<void> _seed() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    await ref.read(recordsRepositoryProvider).createAll(ws, [
      for (final item in fundingSeed) (type: 'funding_opportunity', id: ref.read(recordsRepositoryProvider).newId(), data: item),
    ]);
    unawaited(_sync());
  }
  Future<void> _add() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    final data = await showDialog<Map<String,Object?>>(context: context, builder: (_) => const _FundingDialog());
    if (data == null) return;
    await ref.read(recordsRepositoryProvider).create(ws, 'funding_opportunity', data);
    unawaited(_sync());
  }
  @override Widget build(BuildContext context) {
    final all = ref.watch(recordsProvider('funding_opportunity')).value ?? const <Rec>[];
    final now = ref.watch(clockProvider).now();
    final visible = all.where((o) {
      final hay = '${o.str('title')} ${o.str('organisation')} ${o.str('category')} ${o.str('eligibility_notes')}'.toLowerCase();
      return (_query.isEmpty || hay.contains(_query)) && (_status == null || o.s('status') == _status) && (_priority == null || o.s('priority') == _priority);
    }).toList()..sort((a,b) => (a.dt('deadline_at') ?? DateTime.utc(9999)).compareTo(b.dt('deadline_at') ?? DateTime.utc(9999)));
    final open = all.where((o) => !{'submitted','awarded','rejected','not_eligible'}.contains(o.s('status'))).length;
    final urgent = all.where((o) { final d=o.dt('deadline_at'); return d != null && d.difference(now).inDays <= 30 && d.isAfter(now) && !{'submitted','awarded','rejected','not_eligible'}.contains(o.s('status')); }).length;
    return Scaffold(appBar: AppBar(title: const Text('Funding & opportunities'), actions:[IconButton(tooltip:'Refresh',onPressed:_sync,icon:const Icon(Icons.refresh)), IconButton(tooltip:'Add opportunity',onPressed:_add,icon:const Icon(Icons.add))]),
      body: Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,4), child: Row(children:[_Stat('Open', '$open', Icons.track_changes), const SizedBox(width:12), _Stat('Due in 30 days', '$urgent', Icons.alarm, attention: urgent>0)])),
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0), child: TextField(onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase()), decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search opportunities',isDense:true))),
        SizedBox(height:52, child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),children:[_chip('All statuses',null,_status,(v)=>setState(()=>_status=v)), for(final s in fundingStatuses)_chip(pretty(s),s,_status,(v)=>setState(()=>_status=v)), _chip('Any priority',null,_priority,(v)=>setState(()=>_priority=v)), for(final p in fundingPriorities)_chip(pretty(p),p,_priority,(v)=>setState(()=>_priority=v))])),
        Expanded(child: all.isEmpty ? Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('No funding opportunities yet.'),const SizedBox(height:12),FilledButton.icon(onPressed:_seed,icon:const Icon(Icons.file_download_outlined),label:const Text('Load MPhil tracker'))]) : visible.isEmpty ? const Center(child:Text('No opportunities match these filters.')) : ListView.builder(padding:const EdgeInsets.only(bottom:88),itemCount:visible.length,itemBuilder:(_,i)=>_OpportunityTile(o:visible[i],onEdit:()=>_edit(visible[i])))),
      ]), floatingActionButton:FloatingActionButton.extended(onPressed:_add,icon:const Icon(Icons.add),label:const Text('Opportunity')));
  }
  Widget _chip(String label,String? value,String? current,ValueChanged<String?> onSelected)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(label),selected:value==current,onSelected:(_)=>onSelected(value)));
  Future<void> _edit(Rec opportunity) async { final data=await showDialog<Map<String,Object?>>(context:context,builder:(_)=>_FundingDialog(existing:opportunity)); if(data==null)return; await ref.read(recordsRepositoryProvider).change(opportunity.id,data); unawaited(_sync()); }
}
class _Stat extends StatelessWidget { const _Stat(this.label,this.value,this.icon,{this.attention=false}); final String label,value; final IconData icon; final bool attention; @override Widget build(BuildContext c)=>Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,color:attention?Theme.of(c).colorScheme.error:null),const SizedBox(width:8),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:Theme.of(c).textTheme.titleLarge),Text(label)])]))); }
class _OpportunityTile extends StatelessWidget { const _OpportunityTile({required this.o,required this.onEdit}); final Rec o; final VoidCallback onEdit; @override Widget build(BuildContext c){final d=o.dt('deadline_at');final days=d==null?null:d.difference(DateTime.now()).inDays;final urgent=days!=null&&days>=0&&days<=30;return Card(margin:const EdgeInsets.fromLTRB(12,4,12,4),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:6),onTap:onEdit,title:Text(o.str('title')),subtitle:Text('${o.str('organisation')} · ${o.str('category')}\n${o.str('amount')}${d==null?'':' · deadline ${MaterialLocalizations.of(c).formatMediumDate(d.toLocal())}'}${o.str('next_action').isEmpty?'':'\nNext: ${o.str('next_action')}'}',maxLines:4,overflow:TextOverflow.ellipsis),isThreeLine:true,leading:Icon(o.s('priority')=='high'?Icons.priority_high:Icons.bookmark_outline,color:o.s('priority')=='high'?Theme.of(c).colorScheme.error:null),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Chip(label:Text(pretty(o.str('status'))),visualDensity:VisualDensity.compact),if(urgent)Text('${days}d left',style:TextStyle(color:Theme.of(c).colorScheme.error,fontWeight:FontWeight.bold))])));}}
class _FundingDialog extends StatefulWidget { const _FundingDialog({this.existing}); final Rec? existing; @override State<_FundingDialog> createState()=>_FundingDialogState(); }
class _FundingDialogState extends State<_FundingDialog>{late final _title=TextEditingController(text:widget.existing?.str('title'));late final _org=TextEditingController(text:widget.existing?.str('organisation'));late final _category=TextEditingController(text:widget.existing?.str('category'));late final _amount=TextEditingController(text:widget.existing?.str('amount'));late final _deadline=TextEditingController(text:widget.existing?.dt('deadline_at')?.toIso8601String().substring(0,10));late final _next=TextEditingController(text:widget.existing?.str('next_action'));late final _notes=TextEditingController(text:widget.existing?.str('eligibility_notes'));late String _status=widget.existing?.str('status','not_started')??'not_started';late String _priority=widget.existing?.str('priority','medium')??'medium';@override void dispose(){for(final c in[_title,_org,_category,_amount,_deadline,_next,_notes])c.dispose();super.dispose();} @override Widget build(BuildContext c)=>AlertDialog(title:Text(widget.existing==null?'New opportunity':'Edit opportunity'),content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:_title,decoration:const InputDecoration(labelText:'Opportunity')),TextField(controller:_org,decoration:const InputDecoration(labelText:'Organisation')),TextField(controller:_category,decoration:const InputDecoration(labelText:'Category')),TextField(controller:_amount,decoration:const InputDecoration(labelText:'Amount / support')),TextField(controller:_deadline,decoration:const InputDecoration(labelText:'Deadline (YYYY-MM-DD, optional)')),Row(children:[Expanded(child:DropdownButtonFormField<String>(value:_priority,decoration:const InputDecoration(labelText:'Priority'),items:[for(final p in fundingPriorities)DropdownMenuItem(value:p,child:Text(pretty(p)))],onChanged:(v)=>setState(()=>_priority=v!))),const SizedBox(width:12),Expanded(child:DropdownButtonFormField<String>(value:_status,decoration:const InputDecoration(labelText:'Status'),items:[for(final s in fundingStatuses)DropdownMenuItem(value:s,child:Text(pretty(s)))],onChanged:(v)=>setState(()=>_status=v!)))]),TextField(controller:_next,decoration:const InputDecoration(labelText:'Next action')),TextField(controller:_notes,maxLines:4,decoration:const InputDecoration(labelText:'Eligibility / notes'))]))),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:(){final title=_title.text.trim();final org=_org.text.trim();if(title.isEmpty||org.isEmpty)return;final d=DateTime.tryParse(_deadline.text.trim());Navigator.pop(c,<String,Object?>{'title':title,'organisation':org,'category':_category.text.trim().isEmpty?'Other':_category.text.trim(),'amount':_amount.text.trim().isEmpty?null:_amount.text.trim(),'deadline_at':d,'deadline_type':d==null?'Not announced':'Confirmed','priority':_priority,'status':_status,'next_action':_next.text.trim().isEmpty?null:_next.text.trim(),'eligibility_notes':_notes.text.trim().isEmpty?null:_notes.text.trim()});},child:const Text('Save'))]);}
}
