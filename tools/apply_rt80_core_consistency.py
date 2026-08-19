from pathlib import Path

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]


def patch_text(text:str)->str:
    replacements={
        '<title>Reinos Tribais — RT79.1 Revisado</title>':'<title>Reinos Tribais — RT80.5</title>',
        'const RT_BUILD = "79.1";':'const RT_BUILD = "80.5";',
        "[17,18,19,20,21,22,23,24,25,49,50,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78].includes(Number(parsed.version))":"[17,18,19,20,21,22,23,24,25,49,50,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79].includes(Number(parsed.version))",
        'CENTRAL OPERACIONAL RT79.1':'CENTRAL OPERACIONAL RT80.5',
        'interface guiada RT79.1':'interface guiada RT80.5',
        'RT79.1 com os 19 edifícios ancorados pelos lotes':'RT80.5 com os 19 edifícios ancorados pelos lotes',
    }
    for old,new in replacements.items():
        if old not in text:
            raise SystemExit(f'anchor missing: {old[:90]}')
        text=text.replace(old,new)
    return text


def main():
    for path in FILES:
        original=path.read_text(encoding='utf-8')
        patched=patch_text(original)
        path.write_text(patched,encoding='utf-8')
        print(path, 'changed', original!=patched)

if __name__=='__main__':
    main()
