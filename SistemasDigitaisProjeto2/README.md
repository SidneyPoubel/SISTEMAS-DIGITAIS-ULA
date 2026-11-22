# Teclado PS/2 → LCD com Tradução Morse

Projeto em VHDL para a placa **Xilinx Spartan-3AN** (clock de 50 MHz). Ele lê teclas de um teclado PS/2, mostra os caracteres digitados na **linha 1** de um LCD 16x2 (modo 4 bits) e exibe a tradução em código Morse na **linha 2**.

O número de caracteres é limitado a **5**.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `teclado_morse_lcd.vhd` | Módulo principal (receptor PS/2, tradutor, controlador do LCD) |
| `tb_teclado.vhd` | Testbench que simula um teclado PS/2 enviando teclas |

## Como funciona

O design é dividido em quatro blocos (processos):

1. **Receptor PS/2:** sincroniza o `ps2_clk` com o clock do sistema, detecta a borda de descida e desloca os bits de dados para um registrador de 11 bits (start + 8 dados + paridade + stop). Ao completar um quadro, gera um pulso `scan_ready` com o scan code de 8 bits.
2. **Tradutor scan code → ASCII/Morse:** converte o scan code em ASCII e no padrão Morse correspondente, e guarda os dois em buffers. Trata o *break code* (`F0`, liberação de tecla) ignorando o scan code seguinte, e a tecla Backspace (`66`) apagando o último caractere e seus símbolos Morse.
3. **Base de tempo do LCD:** gera o pulso `lcd_tick`, que dita o ritmo da máquina de estados do LCD.
4. **Controlador do LCD (FSM):** inicializa o LCD em modo 4 bits e depois atualiza as duas linhas continuamente a partir dos buffers. Cada byte é enviado em 4 sub-passos (nibble alto com E em 1, E em 0, nibble baixo com E em 1, E em 0).

### Formato do Morse

Cada letra ocupa `sym_len` posições no buffer: os símbolos (`.` e `-`) mais uma posição em branco como separador. Por exemplo, `A` (`.-`) usa 3 posições. A tecla de espaço usa 3 posições em branco.

O buffer Morse tem 16 posições e é exibido inteiro na linha 2.

## Interface

| Porta | Direção | Descrição |
|---|---|---|
| `clk` | entrada | Clock de 50 MHz |
| `rst` | entrada | Reset síncrono, ativo em nível alto |
| `ps2_clk` | entrada | Clock do teclado PS/2 |
| `ps2_data` | entrada | Dados do teclado PS/2 |
| `lcd_rs` | saída | Seleção de registrador (0 = comando, 1 = dado) |
| `lcd_rw` | saída | Fixo em `'0'` (somente escrita) |
| `lcd_e` | saída | Enable do LCD |
| `lcd_data[3:0]` | saída | Barramento de dados de 4 bits (D7..D4) |

Os pinos físicos devem ser definidos no arquivo de restrições (`.ucf`) conforme a sua placa e o seu LCD.

## Teclas suportadas

- Letras **A–Z** (scan codes do Set 2 do PS/2)
- **Espaço**
- **Backspace** (apaga o último caractere)

Qualquer outra tecla é ignorada.

## Simulação

O testbench `tb_teclado.vhd`:

1. Aplica reset e aguarda 16 ms (inicialização do LCD);
2. Envia a tecla **A** (`1C`);
3. Envia a tecla **B** (`32`);
4. Envia a liberação de **B** (`F0`, `32`).

Cada quadro PS/2 usa um clock de 80 µs por bit, com paridade ímpar. Para simular no ModelSim:

```
vcom teclado_morse_lcd.vhd
vcom tb_teclado.vhd
vsim work.tb_teclado
run 30 ms
```

Observe `lcd_rs`, `lcd_e` e `lcd_data` para acompanhar os comandos de inicialização e os caracteres enviados às duas linhas.

## Pontos de atenção

Observações sobre o código atual, úteis antes de testar na placa:

- **Tempo do LCD:** com `clk_cnt = 5`, o `lcd_tick` ocorre a cada 6 ciclos de clock (~120 ns). Isso é adequado para simulação, mas um LCD real normalmente exige tempos bem maiores entre comandos (dezenas de µs a alguns ms) e esperas na inicialização. Para hardware, é preciso aumentar esse valor e/ou incluir atrasos.
- **Tamanho do buffer Morse:** o buffer tem 16 posições, mas 5 caracteres podem ocupar até 25. Dependendo do texto digitado, pode haver acesso fora dos limites.
- **Espaço:** conta como um dos 5 caracteres e ocupa 3 posições no Morse.
- **Teclas estendidas:** códigos com prefixo `E0` não são tratados.
