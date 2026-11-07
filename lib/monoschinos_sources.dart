import 'monoschinos_client.dart';

/// Fuentes de MonosChinos que se muestran y se pueden usar.
/// MonosChinos2 (monoschinos.st) queda inhabilitada: si existe en monosSites,
/// no aparece en el menú ni se puede abrir.
const _disabledMonosLabels = {'MonosChinos2'};

/// Fuentes que el usuario apagó en Ajustes. Se guarda en library.json
/// (clave 'disabledMonos') y la carga/guarda la Library principal.
final Set<String> userDisabledMonosLabels = {};

bool monosSiteEnabled(int index) =>
    index >= 0 &&
    index < monosSites.length &&
    !_disabledMonosLabels.contains(monosSites[index].label) &&
    !userDisabledMonosLabels.contains(monosSites[index].label);

/// Fuentes que aparecen con interruptor en Ajustes (todas menos las
/// inhabilitadas para siempre).
List<int> get switchableMonosSiteIndexes => [
  for (var i = 0; i < monosSites.length; i++)
    if (!_disabledMonosLabels.contains(monosSites[i].label)) i,
];

List<int> get enabledMonosSiteIndexes => [
  for (var i = 0; i < monosSites.length; i++)
    if (monosSiteEnabled(i)) i,
];
