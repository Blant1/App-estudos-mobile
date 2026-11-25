import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const StudyPlannerApp());
}

class StudyPlannerApp extends StatelessWidget {
  const StudyPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cronograma de Estudos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      home: const StudyPlannerScreen(),
    );
  }
}

class Materia {
  final String id;
  String nome;
  int tempoMinutos;
  int intervaloAposMinutos;
  final Color cor;
  bool concluida;

  Materia({
    required this.id,
    required this.nome,
    required this.tempoMinutos,
    required this.intervaloAposMinutos,
    required this.cor,
    this.concluida = false,
  });
}

class EtapaCronograma {
  final String titulo;
  final int duracaoMinutos;
  final bool isIntervalo;
  final Color cor;
  final Materia? materiaRef;

  EtapaCronograma({
    required this.titulo,
    required this.duracaoMinutos,
    required this.isIntervalo,
    required this.cor,
    this.materiaRef,
  });
}

class StudyPlannerScreen extends StatefulWidget {
  const StudyPlannerScreen({super.key});

  @override
  State<StudyPlannerScreen> createState() => _StudyPlannerScreenState();
}

class _StudyPlannerScreenState extends State<StudyPlannerScreen> {
  final TextEditingController _materiaController = TextEditingController();
  final TextEditingController _horasController = TextEditingController(text: '2');
  final TextEditingController _minutosController = TextEditingController(text: '0');
  final TextEditingController _intervaloController = TextEditingController(text: '10');

  final List<Materia> _materias = [];
  int _tempoTotalMinutos = 120;
  int _minutosIntervaloPadrao = 10;

  Timer? _timer;
  bool _sessaoIniciada = false;
  bool _estaRodando = false;
  int _etapaAtualIndex = 0;
  int _segundosRestantes = 0;

  final Stopwatch _stopwatchSessao = Stopwatch();
  int _segundosTotaisSessaoReal = 0;
  List<EtapaCronograma> _filaExecucao = [];

  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<Color> _coresDisponiveis = [
    Colors.indigo,
    Colors.teal,
    Colors.deepOrange,
    Colors.purple,
    Colors.blue,
    Colors.pink,
    Colors.amber.shade800,
    Colors.cyan.shade700,
  ];

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    _materiaController.dispose();
    _horasController.dispose();
    _minutosController.dispose();
    _intervaloController.dispose();
    super.dispose();
  }

  void _atualizarTempoTotalDigitado() {
    if (_sessaoIniciada) return;
    final horas = int.tryParse(_horasController.text) ?? 0;
    final minutos = int.tryParse(_minutosController.text) ?? 0;
    final intervalo = int.tryParse(_intervaloController.text) ?? 0;

    setState(() {
      _tempoTotalMinutos = (horas * 60) + minutos;
      _minutosIntervaloPadrao = intervalo;
    });
  }

  void _sincronizarTempoTotalComAvancado() {
    if (_materias.isEmpty) return;
    int somaEstudo = 0;
    int somaIntervalos = 0;

    for (int i = 0; i < _materias.length; i++) {
      somaEstudo += _materias[i].tempoMinutos;
      if (i < _materias.length - 1) {
        somaIntervalos += _materias[i].intervaloAposMinutos;
      }
    }

    final int totalGeral = somaEstudo + somaIntervalos;
    setState(() {
      _tempoTotalMinutos = totalGeral;
      _horasController.text = (totalGeral ~/ 60).toString();
      _minutosController.text = (totalGeral % 60).toString();
    });
  }

  void _adicionarMateria() {
    if (_sessaoIniciada) return;
    final nome = _materiaController.text.trim();
    if (nome.isEmpty) return;

    setState(() {
      final cor = _coresDisponiveis[_materias.length % _coresDisponiveis.length];

      _materias.add(
        Materia(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          nome: nome,
          tempoMinutos: 30,
          intervaloAposMinutos: _minutosIntervaloPadrao,
          cor: cor,
        ),
      );
      _materiaController.clear();
      _sincronizarTempoTotalComAvancado();
    });
  }

  void _removerMateria(String id) {
    if (_sessaoIniciada) return;
    setState(() {
      _materias.removeWhere((m) => m.id == id);
      _sincronizarTempoTotalComAvancado();
    });
  }

  List<EtapaCronograma> _montarFilaExecucao() {
    final List<EtapaCronograma> fila = [];

    for (int i = 0; i < _materias.length; i++) {
      final m = _materias[i];
      fila.add(
        EtapaCronograma(
          titulo: m.nome,
          duracaoMinutos: m.tempoMinutos,
          isIntervalo: false,
          cor: m.cor,
          materiaRef: m,
        ),
      );

      if (i < _materias.length - 1 && m.intervaloAposMinutos > 0) {
        fila.add(
          EtapaCronograma(
            titulo: 'Intervalo / Descanso',
            duracaoMinutos: m.intervaloAposMinutos,
            isIntervalo: true,
            cor: Colors.green,
          ),
        );
      }
    }
    return fila;
  }

  void _iniciarSessaoDeEstudos() {
    if (_materias.isEmpty) return;

    setState(() {
      for (var m in _materias) {
        m.concluida = false;
      }
      _filaExecucao = _montarFilaExecucao();
      _etapaAtualIndex = 0;
      _segundosRestantes = _filaExecucao[0].duracaoMinutos * 60;
      _sessaoIniciada = true;
      _estaRodando = true;
    });

    _stopwatchSessao.reset();
    _stopwatchSessao.start();
    _iniciarTickTimer();
  }

  void _iniciarTickTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes > 0) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        _timer?.cancel();
        setState(() {
          _estaRodando = false;
        });
        _aoFinalizarEtapaAtual();
      }
    });
  }

  void _pausarOuRetomar() {
    if (_estaRodando) {
      _timer?.cancel();
      _stopwatchSessao.stop();
      setState(() => _estaRodando = false);
    } else {
      setState(() => _estaRodando = true);
      _stopwatchSessao.start();
      _iniciarTickTimer();
    }
  }

  void _encerrarSessaoManualmente() {
    _timer?.cancel();
    _stopwatchSessao.stop();
    setState(() {
      _sessaoIniciada = false;
      _estaRodando = false;
      _filaExecucao.clear();
    });
  }

  void _pularEtapaAtual() {
    _timer?.cancel();
    setState(() {
      _segundosRestantes = 0;
      _estaRodando = false;
    });
    _aoFinalizarEtapaAtual();
  }

  void _aoFinalizarEtapaAtual() {
    final etapaConcluida = _filaExecucao[_etapaAtualIndex];

    if (!etapaConcluida.isIntervalo && etapaConcluida.materiaRef != null) {
      setState(() {
        etapaConcluida.materiaRef!.concluida = true;
      });
    }

    if (_etapaAtualIndex + 1 < _filaExecucao.length) {
      _tocarSomIntermediario();
      final proximaEtapa = _filaExecucao[_etapaAtualIndex + 1];
      _exibirDialogoTransicao(etapaConcluida, proximaEtapa);
    } else {
      _stopwatchSessao.stop();
      _segundosTotaisSessaoReal = _stopwatchSessao.elapsed.inSeconds;
      _tocarSomConclusaoFinal();
      _exibirDialogoParabensFinal();
    }
  }

  Future<void> _tocarSomIntermediario() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/som2.mp3'));
    } catch (e) {
      debugPrint('Erro ao reproduzir som 2: $e');
    }
  }

  Future<void> _tocarSomConclusaoFinal() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/concluido.mp3'));
    } catch (e) {
      debugPrint('Erro ao reproduzir som concluido: $e');
    }
  }

  void _exibirDialogoTransicao(EtapaCronograma atual, EtapaCronograma proxima) {
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Icon(
            atual.isIntervalo ? Icons.notifications_active : Icons.check_circle_outline,
            color: proxima.cor,
            size: 48,
          ),
          title: Text(
            atual.isIntervalo
                ? 'O intervalo acabou! Voltando aos estudos...'
                : 'Tempo de ${atual.titulo} finalizado!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A seguir no seu cronograma:',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: proxima.cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: proxima.cor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      proxima.titulo,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: proxima.cor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duração: ${_formatarTempo(proxima.duracaoMinutos)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: proxima.cor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _etapaAtualIndex++;
                  _segundosRestantes = _filaExecucao[_etapaAtualIndex].duracaoMinutos * 60;
                  _estaRodando = true;
                });
                _stopwatchSessao.start();
                _iniciarTickTimer();
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                proxima.isIntervalo ? 'Iniciar Intervalo' : 'Iniciar Próxima Matéria',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: proxima.cor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  void _exibirDialogoParabensFinal() {
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    final String textoTempoReal = _formatarTempoDetalhado(_segundosTotaisSessaoReal);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(
            Icons.emoji_events_rounded,
            color: Colors.amber,
            size: 64,
          ),
          title: const Text(
            'Parabéns! Estudos Concluídos!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Você completou todas as etapas do seu plano com sucesso!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer, color: Colors.indigo.shade700),
                    const SizedBox(width: 10),
                    Text(
                      'Tempo total dedicado: $textoTempoReal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _encerrarSessaoManualmente();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: const Text('Concluir'),
            ),
          ],
        );
      },
    );
  }

  String _formatarTempo(int totalMinutos) {
    if (totalMinutos <= 0) return '0 min';
    final horas = totalMinutos ~/ 60;
    final minutos = totalMinutos % 60;

    if (horas > 0 && minutos > 0) {
      return '${horas}h ${minutos}min';
    } else if (horas > 0) {
      return '${horas}h';
    } else {
      return '${minutos} min';
    }
  }

  String _formatarTempoDetalhado(int totalSegundos) {
    if (totalSegundos < 60) return '$totalSegundos segundos';
    final horas = totalSegundos ~/ 3600;
    final minutos = (totalSegundos % 3600) ~/ 60;

    if (horas > 0 && minutos > 0) {
      return '$horas hora(s) e $minutos minuto(s)';
    } else if (horas > 0) {
      return '$horas hora(s)';
    } else {
      return '$minutos minuto(s)';
    }
  }

  String _formatarRelogio(int totalSegundos) {
    final horas = totalSegundos ~/ 3600;
    final minutos = (totalSegundos % 3600) ~/ 60;
    final segundos = totalSegundos % 60;

    final minStr = minutos.toString().padLeft(2, '0');
    final segStr = segundos.toString().padLeft(2, '0');

    if (horas > 0) {
      return '${horas.toString().padLeft(2, '0')}:$minStr:$segStr';
    }
    return '$minStr:$segStr';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories_rounded),
            SizedBox(width: 12),
            Text(
              'Planejador de Estudos Diário',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 850;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1250),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: _buildFormularioCard(context)),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                if (_sessaoIniciada) ...[
                                  _buildPainelCronometroAtivo(),
                                  const SizedBox(height: 24),
                                ],
                                _buildTabelaCard(context),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          if (_sessaoIniciada) ...[
                            _buildPainelCronometroAtivo(),
                            const SizedBox(height: 24),
                          ],
                          _buildFormularioCard(context),
                          const SizedBox(height: 24),
                          _buildTabelaCard(context),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPainelCronometroAtivo() {
    final etapa = _filaExecucao[_etapaAtualIndex];
    final totalSegundosEtapa = etapa.duracaoMinutos * 60;
    final progresso = totalSegundosEtapa > 0
        ? (_segundosRestantes / totalSegundosEtapa).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 4,
      shadowColor: etapa.cor.withValues(alpha: 0.3),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: etapa.cor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  avatar: Icon(
                    etapa.isIntervalo ? Icons.coffee : Icons.menu_book,
                    size: 18,
                    color: etapa.cor,
                  ),
                  label: Text(
                    etapa.isIntervalo ? 'INTERVALO EM ANDAMENTO' : 'ESTUDANDO AGORA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: etapa.cor,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: etapa.cor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                ),
                Text(
                  'Etapa ${_etapaAtualIndex + 1} de ${_filaExecucao.length}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              etapa.titulo,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _formatarRelogio(_segundosRestantes),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: etapa.cor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progresso,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(etapa.cor),
              ),
            ),
            const SizedBox(height: 20),

            if (etapa.isIntervalo) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🎮 Hora do Intervalo: Escolha um jogo para relaxar!',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _abrirTelaDeJogo('Cobrinha'),
                          icon: const Icon(Icons.videogame_asset),
                          label: const Text('Cobrinha'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _abrirTelaDeJogo('Pac-Man'),
                          icon: const Icon(Icons.sports_esports),
                          label: const Text('Pac-Man'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _abrirTelaDeJogo('Campo Minado'),
                          icon: const Icon(Icons.pest_control),
                          label: const Text('Campo Minado'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pausarOuRetomar,
                  icon: Icon(_estaRodando ? Icons.pause : Icons.play_arrow),
                  label: Text(_estaRodando ? 'Pausar' : 'Retomar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: etapa.cor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pularEtapaAtual,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Concluir etapa agora'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _encerrarSessaoManualmente,
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                  label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _abrirTelaDeJogo(String tipoJogo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TelaMinigame(tipoJogo: tipoJogo),
      ),
    );
  }

  Widget _buildFormularioCard(BuildContext context) {
    final bool podeIniciar = !_sessaoIniciada && _materias.isNotEmpty;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '1. Ajustes e Avançado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                OutlinedButton.icon(
                  onPressed: _materias.isEmpty || _sessaoIniciada
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TelaAvancada(materias: _materias),
                            ),
                          );
                          _sincronizarTempoTotalComAvancado();
                        },
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Avançado'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _horasController,
                    enabled: !_sessaoIniciada,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Horas',
                      prefixIcon: Icon(Icons.access_time),
                    ),
                    onChanged: (_) => _atualizarTempoTotalDigitado(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minutosController,
                    enabled: !_sessaoIniciada,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Minutos',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    onChanged: (_) => _atualizarTempoTotalDigitado(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _intervaloController,
              enabled: !_sessaoIniciada,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Intervalo padrão entre matérias (min)',
                helperText: 'Aplicado automaticamente às novas matérias',
                prefixIcon: Icon(Icons.coffee_outlined),
              ),
              onChanged: (_) => _atualizarTempoTotalDigitado(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Divider(),
            ),
            const Text(
              '2. Adicionar matérias',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _materiaController,
                    enabled: !_sessaoIniciada,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nome da matéria',
                      hintText: 'Ex: Matemática, Inglês...',
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                    onSubmitted: (_) => _adicionarMateria(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _sessaoIniciada ? null : _adicionarMateria,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.pie_chart_outline_rounded, color: Colors.indigo.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tempo total planejado: ${_formatarTempo(_tempoTotalMinutos)}',
                      style: TextStyle(
                        color: Colors.indigo.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: podeIniciar ? _iniciarSessaoDeEstudos : null,
                icon: const Icon(Icons.play_circle_fill_rounded, size: 24),
                label: Text(
                  _sessaoIniciada ? 'Cronograma em andamento...' : 'Começar a Estudar',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabelaCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cronograma de Hoje',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_materias.isNotEmpty && !_sessaoIniciada)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _materias.clear();
                      _sincronizarTempoTotalComAvancado();
                    }),
                    icon: const Icon(Icons.delete_sweep, size: 20),
                    label: const Text('Limpar tudo'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_materias.isEmpty)
              _buildEstadoVazio()
            else
              SizedBox(
                width: double.infinity,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 62,
                  columns: const [
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Atividade', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Duração', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _gerarLinhasDaTabela(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _gerarLinhasDaTabela() {
    final List<DataRow> linhas = [];

    for (int i = 0; i < _materias.length; i++) {
      final materia = _materias[i];

      linhas.add(
        DataRow(
          selected: materia.concluida,
          cells: [
            DataCell(
              Checkbox(
                value: materia.concluida,
                activeColor: materia.cor,
                onChanged: (val) {
                  setState(() {
                    materia.concluida = val ?? false;
                  });
                },
              ),
            ),
            DataCell(
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: materia.cor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    materia.nome,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: materia.concluida ? TextDecoration.lineThrough : null,
                      color: materia.concluida ? Colors.grey : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: materia.cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _formatarTempo(materia.tempoMinutos),
                  style: TextStyle(color: materia.cor, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            DataCell(
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                tooltip: 'Remover matéria',
                onPressed: _sessaoIniciada ? null : () => _removerMateria(materia.id),
              ),
            ),
          ],
        ),
      );

      if (i < _materias.length - 1 && materia.intervaloAposMinutos > 0) {
        linhas.add(
          DataRow(
            color: WidgetStateProperty.all(Colors.green.shade50.withValues(alpha: 0.5)),
            cells: [
              const DataCell(Padding(padding: EdgeInsets.only(left: 12.0), child: Icon(Icons.coffee_rounded, size: 20, color: Colors.green))),
              DataCell(
                Text(
                  'Intervalo após ${materia.nome}',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    _formatarTempo(materia.intervaloAposMinutos),
                    style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const DataCell(SizedBox.shrink()),
            ],
          ),
        );
      }
    }

    return linhas;
  }

  Widget _buildEstadoVazio() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.table_chart_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Nenhuma matéria adicionada ainda',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione as matérias e use o menu Avançado para ajustar os tempos individualmente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class TelaAvancada extends StatefulWidget {
  final List<Materia> materias;

  const TelaAvancada({super.key, required this.materias});

  @override
  State<TelaAvancada> createState() => _TelaAvancadaState();
}

class _TelaAvancadaState extends State<TelaAvancada> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Configuração Avançada de Tempos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajuste fino por Matéria',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Personalize os minutos de cada matéria e o intervalo correspondente.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.materias.length,
                  itemBuilder: (context, index) {
                    final materia = widget.materias[index];
                    final bool isUltima = index == widget.materias.length - 1;

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(color: materia.cor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    materia.nome,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: materia.tempoMinutos.toString(),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(
                                      labelText: 'Estudo (minutos)',
                                      prefixIcon: Icon(Icons.timer_outlined),
                                    ),
                                    onChanged: (val) {
                                      materia.tempoMinutos = int.tryParse(val) ?? 0;
                                    },
                                  ),
                                ),
                                if (!isUltima) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: materia.intervaloAposMinutos.toString(),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      decoration: const InputDecoration(
                                        labelText: 'Intervalo pós (min)',
                                        prefixIcon: Icon(Icons.coffee_outlined),
                                      ),
                                      onChanged: (val) {
                                        materia.intervaloAposMinutos = int.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Salvar e Atualizar Tempo Total', style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// TELA DE MINIGAMES INTEGRADOS (COBRINHA, PAC-MAN E CAMPO MINADO)
// =========================================================================
class TelaMinigame extends StatelessWidget {
  final String tipoJogo;

  const TelaMinigame({super.key, required this.tipoJogo});

  @override
  Widget build(BuildContext context) {
    Widget jogoSelecionado;

    if (tipoJogo == 'Cobrinha') {
      jogoSelecionado = const JogoCobrinha();
    } else if (tipoJogo == 'Pac-Man') {
      jogoSelecionado = const JogoPacMan();
    } else {
      jogoSelecionado = const JogoCampoMinado();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        title: Text('Intervalo: $tipoJogo'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: jogoSelecionado,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 1. JOGO DA COBRINHA (SNAKE)
// -------------------------------------------------------------------------
class JogoCobrinha extends StatefulWidget {
  const JogoCobrinha({super.key});

  @override
  State<JogoCobrinha> createState() => _JogoCobrinhaState();
}

class _JogoCobrinhaState extends State<JogoCobrinha> {
  final int linhas = 20;
  final int colunas = 20;
  List<Point<int>> cobrinha = [const Point(5, 10), const Point(4, 10), const Point(3, 10)];
  Point<int> comida = const Point(10, 10);
  String direcao = 'DIREITA';
  Timer? _timer;
  bool rodando = false;
  int pontos = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _iniciar() {
    setState(() {
      cobrinha = [const Point(5, 10), const Point(4, 10), const Point(3, 10)];
      direcao = 'DIREITA';
      pontos = 0;
      _gerarComida();
      rodando = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 180), (_) => _mover());
  }

  void _gerarComida() {
    final rand = Random();
    Point<int> nova;
    do {
      nova = Point(rand.nextInt(colunas), rand.nextInt(linhas));
    } while (cobrinha.contains(nova));
    comida = nova;
  }

  void _mover() {
    if (!mounted) return;
    setState(() {
      final cabeca = cobrinha.first;
      Point<int> nova;
      switch (direcao) {
        case 'CIMA':
          nova = Point(cabeca.x, cabeca.y - 1);
          break;
        case 'BAIXO':
          nova = Point(cabeca.x, cabeca.y + 1);
          break;
        case 'ESQUERDA':
          nova = Point(cabeca.x - 1, cabeca.y);
          break;
        default:
          nova = Point(cabeca.x + 1, cabeca.y);
      }

      if (nova.x < 0 || nova.x >= colunas || nova.y < 0 || nova.y >= linhas || cobrinha.contains(nova)) {
        _timer?.cancel();
        rodando = false;
        return;
      }

      cobrinha.insert(0, nova);
      if (nova == comida) {
        pontos += 10;
        _gerarComida();
      } else {
        cobrinha.removeLast();
      }
    });
  }

  void _mudarDirecao(String nova) {
    if ((direcao == 'CIMA' && nova == 'BAIXO') ||
        (direcao == 'BAIXO' && nova == 'CIMA') ||
        (direcao == 'ESQUERDA' && nova == 'DIREITA') ||
        (direcao == 'DIREITA' && nova == 'ESQUERDA')) {
      return;
    }
    direcao = nova;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) _mudarDirecao('CIMA');
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) _mudarDirecao('BAIXO');
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _mudarDirecao('ESQUERDA');
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) _mudarDirecao('DIREITA');
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pontos: $pontos', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.greenAccent, width: 3),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: comida.x * 16.0,
                  top: comida.y * 16.0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
                ),
                for (int i = 0; i < cobrinha.length; i++)
                  Positioned(
                    left: cobrinha[i].x * 16.0,
                    top: cobrinha[i].y * 16.0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: i == 0 ? Colors.green : Colors.greenAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!rodando)
            FilledButton.icon(
              onPressed: _iniciar,
              icon: const Icon(Icons.refresh),
              label: const Text('Fim de jogo! Jogar de novo'),
            ),
          const SizedBox(height: 12),
          _ControlesDirecionais(onDir: _mudarDirecao),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 2. JOGO PAC-MAN
// -------------------------------------------------------------------------
class JogoPacMan extends StatefulWidget {
  const JogoPacMan({super.key});

  @override
  State<JogoPacMan> createState() => _JogoPacManState();
}

class _JogoPacManState extends State<JogoPacMan> {
  // 0 = vazio, 1 = parede, 2 = pastilha
  final List<List<int>> mapaBase = [
    [1,1,1,1,1,1,1,1,1,1,1,1,1],
    [1,2,2,2,2,2,1,2,2,2,2,2,1],
    [1,2,1,1,2,2,1,2,2,1,1,2,1],
    [1,2,2,2,2,2,2,2,2,2,2,2,1],
    [1,2,1,2,1,1,2,1,1,2,1,2,1],
    [1,2,2,2,2,2,0,2,2,2,2,2,1],
    [1,2,1,2,1,1,2,1,1,2,1,2,1],
    [1,2,2,2,2,2,2,2,2,2,2,2,1],
    [1,2,1,1,2,2,1,2,2,1,1,2,1],
    [1,2,2,2,2,2,1,2,2,2,2,2,1],
    [1,1,1,1,1,1,1,1,1,1,1,1,1],
  ];

  late List<List<int>> mapa;
  Point<int> pacman = const Point(6, 5);
  List<Point<int>> fantasmas = [const Point(1, 1), const Point(11, 9)];
  String direcao = 'PARADO';
  Timer? _timer;
  int pontos = 0;
  bool gameOver = false;
  bool vitoria = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _iniciar() {
    setState(() {
      mapa = mapaBase.map((linha) => List<int>.from(linha)).toList();
      pacman = const Point(6, 5);
      fantasmas = [const Point(1, 1), const Point(11, 9)];
      direcao = 'PARADO';
      pontos = 0;
      gameOver = false;
      vitoria = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 260), (_) => _tick());
  }

  void _tick() {
    if (!mounted || gameOver || vitoria) return;
    setState(() {
      // Move Pac-Man
      Point<int> prox = pacman;
      if (direcao == 'CIMA') prox = Point(pacman.x, pacman.y - 1);
      if (direcao == 'BAIXO') prox = Point(pacman.x, pacman.y + 1);
      if (direcao == 'ESQUERDA') prox = Point(pacman.x - 1, pacman.y);
      if (direcao == 'DIREITA') prox = Point(pacman.x + 1, pacman.y);

      if (mapa[prox.y][prox.x] != 1) {
        pacman = prox;
        if (mapa[pacman.y][pacman.x] == 2) {
          mapa[pacman.y][pacman.x] = 0;
          pontos += 10;
        }
      }

      // Verifica colisão com fantasma
      if (fantasmas.contains(pacman)) {
        gameOver = true;
        _timer?.cancel();
        return;
      }

      // Move Fantasmas aleatoriamente
      final rand = Random();
      for (int i = 0; i < fantasmas.length; i++) {
        final f = fantasmas[i];
        final opcoes = [
          Point(f.x, f.y - 1),
          Point(f.x, f.y + 1),
          Point(f.x - 1, f.y),
          Point(f.x + 1, f.y),
        ].where((p) => mapa[p.y][p.x] != 1).toList();

        if (opcoes.isNotEmpty) {
          fantasmas[i] = opcoes[rand.nextInt(opcoes.length)];
        }
      }

      if (fantasmas.contains(pacman)) {
        gameOver = true;
        _timer?.cancel();
        return;
      }

      // Verifica se comeu todas as pastilhas
      bool temPastilha = mapa.any((linha) => linha.contains(2));
      if (!temPastilha) {
        vitoria = true;
        _timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) direcao = 'CIMA';
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) direcao = 'BAIXO';
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) direcao = 'ESQUERDA';
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) direcao = 'DIREITA';
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pontos: $pontos', style: const TextStyle(color: Colors.yellow, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            color: Colors.black,
            child: Column(
              children: List.generate(mapa.length, (y) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(mapa[y].length, (x) {
                    final ponto = Point(x, y);
                    Widget conteudo = const SizedBox.shrink();

                    if (pacman == ponto) {
                      conteudo = const Icon(Icons.circle, color: Colors.yellow, size: 20);
                    } else if (fantasmas[0] == ponto) {
                      conteudo = const Icon(Icons.smart_toy, color: Colors.redAccent, size: 20);
                    } else if (fantasmas[1] == ponto) {
                      conteudo = const Icon(Icons.smart_toy, color: Colors.cyanAccent, size: 20);
                    } else if (mapa[y][x] == 2) {
                      conteudo = Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                      );
                    }

                    return Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      color: mapa[y][x] == 1 ? Colors.blue.shade900 : Colors.black,
                      child: conteudo,
                    );
                  }),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          if (gameOver || vitoria)
            FilledButton.icon(
              onPressed: _iniciar,
              icon: const Icon(Icons.refresh),
              label: Text(vitoria ? 'Você venceu! Jogar de novo' : 'Pego pelo fantasma! Tentar de novo'),
            ),
          const SizedBox(height: 12),
          _ControlesDirecionais(onDir: (d) => setState(() => direcao = d)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 3. CAMPO MINADO
// -------------------------------------------------------------------------
class JogoCampoMinado extends StatefulWidget {
  const JogoCampoMinado({super.key});

  @override
  State<JogoCampoMinado> createState() => _JogoCampoMinadoState();
}

class _JogoCampoMinadoState extends State<JogoCampoMinado> {
  final int tamanho = 9;
  final int totalMinas = 10;
  late List<List<bool>> minas;
  late List<List<bool>> revelado;
  late List<List<bool>> bandeira;
  late List<List<int>> vizinhos;
  bool fimDeJogo = false;
  bool venceu = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  void _iniciar() {
    minas = List.generate(tamanho, (_) => List.filled(tamanho, false));
    revelado = List.generate(tamanho, (_) => List.filled(tamanho, false));
    bandeira = List.generate(tamanho, (_) => List.filled(tamanho, false));
    vizinhos = List.generate(tamanho, (_) => List.filled(tamanho, 0));
    fimDeJogo = false;
    venceu = false;

    final rand = Random();
    int colocadas = 0;
    while (colocadas < totalMinas) {
      int r = rand.nextInt(tamanho);
      int c = rand.nextInt(tamanho);
      if (!minas[r][c]) {
        minas[r][c] = true;
        colocadas++;
      }
    }

    for (int r = 0; r < tamanho; r++) {
      for (int c = 0; c < tamanho; c++) {
        if (!minas[r][c]) {
          int count = 0;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              int nr = r + dr, nc = c + dc;
              if (nr >= 0 && nr < tamanho && nc >= 0 && nc < tamanho && minas[nr][nc]) {
                count++;
              }
            }
          }
          vizinhos[r][c] = count;
        }
      }
    }
    setState(() {});
  }

  void _revelar(int r, int c) {
    if (fimDeJogo || venceu || revelado[r][c] || bandeira[r][c]) return;

    setState(() {
      if (minas[r][c]) {
        fimDeJogo = true;
        for (int i = 0; i < tamanho; i++) {
          for (int j = 0; j < tamanho; j++) {
            if (minas[i][j]) revelado[i][j] = true;
          }
        }
        return;
      }

      _abrirCascata(r, c);
      _checarVitoria();
    });
  }

  void _abrirCascata(int r, int c) {
    if (r < 0 || r >= tamanho || c < 0 || c >= tamanho || revelado[r][c] || bandeira[r][c]) return;
    revelado[r][c] = true;
    if (vizinhos[r][c] == 0) {
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          _abrirCascata(r + dr, c + dc);
        }
      }
    }
  }

  void _alternarBandeira(int r, int c) {
    if (fimDeJogo || venceu || revelado[r][c]) return;
    setState(() {
      bandeira[r][c] = !bandeira[r][c];
    });
  }

  void _checarVitoria() {
    int segurosRevelados = 0;
    for (int r = 0; r < tamanho; r++) {
      for (int c = 0; c < tamanho; c++) {
        if (revelado[r][c] && !minas[r][c]) segurosRevelados++;
      }
    }
    if (segurosRevelados == (tamanho * tamanho) - totalMinas) {
      venceu = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Toque para abrir | Segure (ou botão direito) para bandeira 🚩',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: List.generate(tamanho, (r) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(tamanho, (c) {
                  final ab = revelado[r][c];
                  final min = minas[r][c];
                  final flag = bandeira[r][c];
                  final num = vizinhos[r][c];

                  return GestureDetector(
                    onTap: () => _revelar(r, c),
                    onLongPress: () => _alternarBandeira(r, c),
                    onSecondaryTap: () => _alternarBandeira(r, c),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.all(2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ab
                            ? (min ? Colors.red : Colors.grey.shade300)
                            : Colors.blueGrey.shade600,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ab
                          ? (min
                              ? const Icon(Icons.brightness_high, size: 18, color: Colors.white)
                              : (num > 0
                                  ? Text(
                                      '$num',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: num == 1
                                            ? Colors.blue.shade800
                                            : (num == 2 ? Colors.green.shade800 : Colors.red.shade800),
                                      ),
                                    )
                                  : null))
                          : (flag ? const Icon(Icons.flag, size: 18, color: Colors.amber) : null),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        if (fimDeJogo || venceu)
          FilledButton.icon(
            onPressed: _iniciar,
            icon: const Icon(Icons.refresh),
            label: Text(venceu ? 'Parabéns, você limpou o campo! Jogar de novo' : 'BUM! Tentar novamente'),
          ),
      ],
    );
  }
}

// Botões direcionais na tela para facilitar o controle em qualquer dispositivo
class _ControlesDirecionais extends StatelessWidget {
  final Function(String) onDir;

  const _ControlesDirecionais({required this.onDir});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          icon: const Icon(Icons.arrow_left, size: 32),
          onPressed: () => onDir('ESQUERDA'),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            IconButton.filled(
              icon: const Icon(Icons.arrow_drop_up, size: 32),
              onPressed: () => onDir('CIMA'),
            ),
            const SizedBox(height: 8),
            IconButton.filled(
              icon: const Icon(Icons.arrow_drop_down, size: 32),
              onPressed: () => onDir('BAIXO'),
            ),
          ],
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          icon: const Icon(Icons.arrow_right, size: 32),
          onPressed: () => onDir('DIREITA'),
        ),
      ],
    );
  }
}