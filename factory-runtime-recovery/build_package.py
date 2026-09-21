"""Build reproducible self-contained CMD; never mutate the installed Factory."""
import base64, hashlib, io, json, pathlib, textwrap, zipfile
root=pathlib.Path(__file__).resolve().parent
out=root.parent/'deliverables'
out.mkdir(exist_ok=True)
for p in root.rglob('*.ps1'):
    s=p.read_text(encoding='utf-8-sig')
    p.write_bytes(b'\xef\xbb\xbf'+s.replace('\r\n','\n').replace('\n','\r\n').encode('utf-8'))
paths=sorted(p for p in root.rglob('*') if p.is_file() and p.suffix in {'.ps1','.md','.json'} and p.name not in {'PACKAGE_MANIFEST.json','Bootstrap.template.ps1'} and '__pycache__' not in p.parts)
manifest={'schema':'factory-recovery-package-v1','base_pr_head':'52287b52f68a86cc27db801008a7c5a284f122c7','files':[{'path':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}
(root/'PACKAGE_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
paths.append(root/'PACKAGE_MANIFEST.json')
buf=io.BytesIO()
with zipfile.ZipFile(buf,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(paths):
        info=zipfile.ZipInfo(p.relative_to(root).as_posix(),date_time=(2026,9,21,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(info,p.read_bytes())
payload=buf.getvalue();sha=hashlib.sha256(payload).hexdigest()
bootstrap=(root/'Bootstrap.template.ps1').read_text(encoding='utf-8-sig').replace('__ZIP_SHA__',sha)
(out/'bootstrap-validated.ps1').write_text(bootstrap,encoding='utf-8-sig')
encoded=base64.b64encode(bootstrap.encode('utf-16le')).decode('ascii')
lines=['@echo off','setlocal DisableDelayedExpansion','set "TANUKI_RECOVERY_SOURCE=%~f0"','set "TANUKI_PS=%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"','if exist "%SystemRoot%\\Sysnative\\WindowsPowerShell\\v1.0\\powershell.exe" set "TANUKI_PS=%SystemRoot%\\Sysnative\\WindowsPowerShell\\v1.0\\powershell.exe"','"%TANUKI_PS%" -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+encoded,'if errorlevel 1 echo {"status":"HOLD","code":"BOOTSTRAP_OR_POWERSHELL_FAILURE","factory_completion_pass":false} > "%~dp0FACTORY_RESULT.json"','exit /b %errorlevel%',':__TANUKI_FACTORY_PAYLOAD__',*textwrap.wrap(base64.b64encode(payload).decode('ascii'),120)]
assert max(map(len,lines))<8191,'CMD line too long'
cmd='\r\n'.join(lines)+'\r\n';cmd.encode('ascii')
final=out/'START_FACTORY_RECOVERY.cmd';final.write_bytes(cmd.encode('ascii'))
info={'file':str(final),'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'embedded_zip_sha256':sha,'size':final.stat().st_size,'max_line':max(map(len,lines)),'payload_files':len(paths)}
(out/'PACKAGE_BUILD.json').write_text(json.dumps(info,indent=2)+'\n')
print(json.dumps(info))
