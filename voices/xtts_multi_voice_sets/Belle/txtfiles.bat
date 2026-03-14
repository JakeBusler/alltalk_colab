@echo off
for %%x in (*) do (
    if not "%%~nx"=="%~n0" type nul > "%%~nx.txt"
)