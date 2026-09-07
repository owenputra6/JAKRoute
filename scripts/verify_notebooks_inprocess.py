"""Execute demo notebook cells without opening a Jupyter socket.

Used in the authoring environment where kernel socket creation is unavailable.
Normal Jupyter users can run the same cells directly. Does not run live APIs.
"""
import ast
import base64
import contextlib
import io
import os
from pathlib import Path
import nbformat
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT=Path(__file__).resolve().parents[1]

def verify():
    os.chdir(ROOT)
    for path in sorted((ROOT/'notebooks').glob('*.ipynb')):
        nb=nbformat.read(path,as_version=4)
        namespace={'__name__':'__notebook__'}
        count=0
        for cell in nb.cells:
            if cell.cell_type!='code': continue
            count+=1
            cell.outputs=[]
            output=io.StringIO()
            def show(*args,**kwargs):
                for num in plt.get_fignums():
                    buf=io.BytesIO();plt.figure(num).savefig(buf,format='png',dpi=160,bbox_inches='tight')
                    cell.outputs.append(nbformat.v4.new_output('display_data',data={'image/png':base64.b64encode(buf.getvalue()).decode(),'text/plain':'Routing simulation figure'},metadata={}))
                    (ROOT/'verification'/'routing_demo.png').write_bytes(buf.getvalue())
                plt.close('all')
            plt.show=show
            parsed=ast.parse(cell.source)
            expr=parsed.body.pop() if parsed.body and isinstance(parsed.body[-1],ast.Expr) else None
            with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
                exec(compile(parsed,str(path),'exec'),namespace)
                result=eval(compile(ast.Expression(expr.value),str(path),'eval'),namespace) if expr else None
            text=output.getvalue()
            if text: cell.outputs.insert(0,nbformat.v4.new_output('stream',name='stdout',text=text))
            if result is not None: cell.outputs.append(nbformat.v4.new_output('execute_result',execution_count=count,data={'text/plain':repr(result)},metadata={}))
            cell.execution_count=count
        nb.metadata['jakroute_verification']={'runner':'in_process_python','live_apis':False,'all_code_cells_passed':True}
        nbformat.validate(nb)
        nbformat.write(nb,path)
        print('PASS',path.name,count,'code cells',flush=True)

if __name__=='__main__': verify()
