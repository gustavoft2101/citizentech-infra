/* AlertaEncosta - painel público do bairro
   Lê data/setores.json (dados simulados) e servidor.json (gerado pelo script
   04-IIS-Aplicacao.ps1 na publicação) e monta a página. Atualiza a cada 60 s.
   Para ligar na API REST da equipe, troque URL_DADOS pelo endpoint da API. */
(function () {
  'use strict';

  var URL_DADOS = 'data/setores.json';
  var URL_SERVIDOR = 'servidor.json';
  var INTERVALO_MS = 60000;
  var INTERVALO_CONEXAO_MS = 5000;   // checagem leve: mostra na hora se o servidor caiu ou voltou

  var NIVEIS = {
    alto:  { rotulo: 'Alto',  ordem: 3, titulo: 'ALERTA ALTO: saia agora pela rota segura' },
    medio: { rotulo: 'Médio', ordem: 2, titulo: 'Atenção: chuva forte em parte do bairro' },
    baixo: { rotulo: 'Baixo', ordem: 1, titulo: 'Sem risco alto no momento' }
  };

  function el(tag, classe, texto) {
    var e = document.createElement(tag);
    if (classe) { e.className = classe; }
    if (texto !== undefined && texto !== null) { e.textContent = texto; }
    return e;
  }

  function semCache(url) {
    return url + (url.indexOf('?') === -1 ? '?' : '&') + 't=' + Date.now();
  }

  // XMLHttpRequest em vez de fetch: funciona até no Internet Explorer do Windows Server 2019.
  function buscarJson(url, sucesso, falha) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', semCache(url), true);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) { return; }
      if (xhr.status === 200) {
        try { sucesso(JSON.parse(xhr.responseText)); }
        catch (e) { falha(new Error('JSON inválido em ' + url)); }
      } else {
        falha(new Error('HTTP ' + xhr.status + ' em ' + url));
      }
    };
    xhr.send();
  }

  function leitura(rotulo, valor, unidade, percentual) {
    var d = el('div');
    d.appendChild(el('dt', null, rotulo));
    var dd = el('dd', null, valor + ' ' + unidade);
    d.appendChild(dd);
    if (typeof percentual === 'number') {
      var barra = el('div', 'barra');
      barra.setAttribute('aria-hidden', 'true');
      var preenchido = el('span');
      preenchido.style.width = Math.max(0, Math.min(100, percentual)) + '%';
      barra.appendChild(preenchido);
      d.appendChild(barra);
    }
    return d;
  }

  function cartaoSetor(s, pontos) {
    var nivel = NIVEIS[s.risco] || NIVEIS.baixo;
    var art = el('article', 'setor setor--' + s.risco);

    var topo = el('div', 'setor__topo');
    var h3 = el('h3', 'setor__nome', s.nome);
    h3.appendChild(el('span', 'setor__id', 'Setor ' + s.id));
    topo.appendChild(h3);
    topo.appendChild(el('span', 'selo selo--' + s.risco, 'Risco ' + nivel.rotulo));
    art.appendChild(topo);

    var dl = el('dl', 'leituras');
    dl.appendChild(leitura('Chuva na última hora', s.chuva1h, 'mm', s.chuva1h / 50 * 100));
    dl.appendChild(leitura('Chuva em 24 h', s.chuva24h, 'mm', s.chuva24h / 120 * 100));
    dl.appendChild(leitura('Umidade do solo', s.umidadeSolo, '%', s.umidadeSolo));
    dl.appendChild(leitura('Nível do córrego', s.nivelCorrego, 'cm', s.nivelCorrego / 160 * 100));
    art.appendChild(dl);

    var ponto = pontos[s.pontoApoio];
    var rota = el('p', 'setor__rota');
    rota.appendChild(el('strong', null, 'Rota segura: '));
    rota.appendChild(document.createTextNode(s.rota));
    if (ponto) { rota.appendChild(document.createTextNode(' Destino: ' + ponto.nome + ', ' + ponto.endereco + '.')); }
    art.appendChild(rota);

    art.appendChild(el('p', 'setor__extra',
      'Probabilidade prevista: ' + Math.round(s.probabilidade * 100) + '% · ' +
      s.moradoresCadastrados + ' moradores cadastrados · ' +
      s.precisamAjuda + ' precisam de ajuda para sair'));
    return art;
  }

  function desenhar(dados) {
    var pontos = {};
    dados.pontosApoio.forEach(function (p) { pontos[p.id] = p; });

    var setores = dados.setores.slice().sort(function (a, b) {
      return (NIVEIS[b.risco] || NIVEIS.baixo).ordem - (NIVEIS[a.risco] || NIVEIS.baixo).ordem;
    });

    // faixa geral: mostra o pior nível entre os setores
    var pior = setores[0] ? setores[0].risco : 'baixo';
    var emPior = setores.filter(function (s) { return s.risco === pior; }).map(function (s) { return s.id + ' ' + s.nome; });
    var faixa = document.getElementById('faixa');
    faixa.className = 'faixa faixa--' + pior;
    faixa.textContent = '';
    faixa.appendChild(el('p', 'faixa__titulo', NIVEIS[pior].titulo));
    faixa.appendChild(el('p', 'faixa__texto',
      pior === 'baixo' ? 'Todos os setores com risco baixo. Continue acompanhando.' :
      'Setor(es) com risco ' + NIVEIS[pior].rotulo.toLowerCase() + ': ' + emPior.join(', ') + '.'));

    var grade = document.getElementById('setores');
    grade.textContent = '';
    setores.forEach(function (s) { grade.appendChild(cartaoSetor(s, pontos)); });

    var lista = document.getElementById('pontos');
    lista.textContent = '';
    dados.pontosApoio.forEach(function (p) {
      var li = el('li');
      li.appendChild(el('strong', null, p.id + ' · ' + p.nome));
      li.appendChild(el('span', null, p.endereco));
      li.appendChild(el('span', null, 'Capacidade: ' + p.capacidade + ' pessoas · ' +
        (p.acessivel ? 'acessível para cadeira de rodas' : 'sem acessibilidade completa')));
      lista.appendChild(li);
    });

    var quando = new Date(dados.atualizadoEm);
    var hora = isNaN(quando) ? new Date() : quando;
    var t = document.getElementById('atualizado');
    t.textContent = hora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    t.setAttribute('datetime', hora.toISOString());
  }

  function erro(e) {
    var faixa = document.getElementById('faixa');
    faixa.className = 'faixa faixa--erro';
    faixa.textContent = '';
    faixa.appendChild(el('p', 'faixa__titulo', 'Não foi possível carregar os dados agora.'));
    faixa.appendChild(el('p', 'faixa__texto', 'Tente de novo em instantes. Em emergência ligue 199. (' + e.message + ')'));
  }

  function carregar() {
    buscarJson(URL_DADOS, function (dados) {
      try { desenhar(dados); } catch (e) { erro(e); }
    }, erro);
  }

  function carregarServidor() {
    var alvo = document.getElementById('servidor');
    buscarJson(URL_SERVIDOR, function (s) {
      alvo.textContent = 'Servido por ' + s.servidor + ' (' + s.ip + ') · domínio ' + s.dominio +
        ' · IIS ' + String(s.iis).replace('Version ', '') + ' · site ' + s.site + ' / pool ' + s.pool + ' · publicado em ' + s.publicadoEm +
        ' · acessado em ' + window.location.host + ' às ' + new Date().toLocaleString('pt-BR');
    }, function () {
      alvo.textContent = 'Servidor: servidor.json não encontrado (ele é gerado pelo script 04-IIS-Aplicacao.ps1 na publicação).';
    });
  }

  // ---------- conexão com o servidor (aparece no topo da página) ----------
  var foraDesde = null;
  var ultimaQueda = '';
  function hora(d) { return d.toLocaleTimeString('pt-BR'); }
  function verificarConexao() {
    var alvo = document.getElementById('conexao');
    buscarJson(URL_SERVIDOR, function (s) {
      var agora = new Date();
      if (foraDesde) {
        // o servidor voltou: guarda o intervalo fora do ar e recarrega os dados
        ultimaQueda = 'fora do ar das ' + hora(foraDesde) + ' às ' + hora(agora) +
          ' (' + Math.round((agora - foraDesde) / 1000) + ' s), voltou sozinho';
        foraDesde = null;
        carregar();
      }
      alvo.textContent = '\u25CF Servidor ' + s.servidor + ' no ar \u00B7 verificado às ' + hora(agora) +
        (ultimaQueda ? ' \u00B7 ' + ultimaQueda : '');
      alvo.className = 'topo__conexao topo__conexao--ok';
    }, function () {
      if (!foraDesde) { foraDesde = new Date(); }
      alvo.textContent = '\u25CF Servidor sem resposta desde ' + hora(foraDesde) + ' \u00B7 tentando de novo a cada 5 s';
      alvo.className = 'topo__conexao topo__conexao--falha';
    });
  }

  // ---------- acessibilidade: preferências lembradas neste navegador ----------
  function lerPreferencia(chave) {
    try { return window.localStorage.getItem(chave) === '1'; } catch (e) { return false; }
  }
  function gravarPreferencia(chave, valor) {
    try { window.localStorage.setItem(chave, valor ? '1' : '0'); } catch (e) { /* sem armazenamento: tudo bem */ }
  }
  function alternador(idBotao, classe, chave) {
    var botao = document.getElementById(idBotao);
    function aplicar(ligado) {
      if (ligado) { document.documentElement.classList.add(classe); }
      else { document.documentElement.classList.remove(classe); }
      botao.setAttribute('aria-pressed', ligado ? 'true' : 'false');
    }
    aplicar(lerPreferencia(chave));
    botao.addEventListener('click', function () {
      var ligado = botao.getAttribute('aria-pressed') !== 'true';
      aplicar(ligado);
      gravarPreferencia(chave, ligado);
    });
  }

  alternador('btn-contraste', 'contraste', 'ae-contraste');
  alternador('btn-fonte', 'fonte-maior', 'ae-fonte');
  carregar();
  carregarServidor();
  verificarConexao();
  setInterval(carregar, INTERVALO_MS);
  setInterval(verificarConexao, INTERVALO_CONEXAO_MS);
}());
