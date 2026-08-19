import os,runpy
# O workflow já valida a exposição HTTPS antes desta etapa. A bateria funcional
# pesada usa o servidor local da mesma revisão para não transformar latência/
# instabilidade do Quick Tunnel em falso defeito do jogo.
os.environ['RT79_TEST_URL']='http://127.0.0.1:8765/'
runpy.run_path('tools/rt79_chrome_fast_regression_base.py',run_name='__main__')
runpy.run_path('tools/rt79_extended_revalidation_selenium.py',run_name='__main__')
