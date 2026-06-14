import sys
import os

file_path = r'c:\Users\Matias\Documents\pruebas-de-concepto\tab_home.tscn'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

blocks = {}
current_block = 'HEADER_IMPORTS'
blocks[current_block] = []

for line in lines:
    if line.startswith('[node name='):
        if 'name="StartButton"' in line:
            current_block = 'START_BUTTON'
        elif 'name="ObjectiveCard"' in line:
            current_block = 'OBJECTIVE_CARD'
        elif 'name="LastSessionCard"' in line:
            current_block = 'LAST_SESSION_CARD'
        elif 'name="StatsPanel"' in line:
            current_block = 'STATS_PANEL'
        elif 'name="InsightsPanel"' in line:
            current_block = 'INSIGHTS_PANEL'
        elif current_block in ['STATS_PANEL', 'INSIGHTS_PANEL'] and 'parent="MainColumn"' not in line:
            pass # keep it in the same block to be deleted
        elif current_block not in ['HEADER_IMPORTS', 'START_BUTTON', 'OBJECTIVE_CARD', 'LAST_SESSION_CARD', 'STATS_PANEL', 'INSIGHTS_PANEL']:
            current_block = 'MAIN'
    
    if current_block not in blocks:
        blocks[current_block] = []
    blocks[current_block].append(line)

# Reassemble
new_lines = []
for k in ['HEADER_IMPORTS', 'MAIN']:
    if k in blocks:
        new_lines.extend(blocks[k])

if 'START_BUTTON' in blocks:
    new_lines.extend(blocks['START_BUTTON'])
if 'OBJECTIVE_CARD' in blocks:
    new_lines.extend(blocks['OBJECTIVE_CARD'])
if 'LAST_SESSION_CARD' in blocks:
    new_lines.extend(blocks['LAST_SESSION_CARD'])

# Note: STATS_PANEL and INSIGHTS_PANEL are intentionally omitted

new_content = ''.join(new_lines)
new_content = new_content.replace('LastSessionCard', 'MascotCard')
new_content = new_content.replace('LastSessionVBox', 'MascotVBox')
new_content = new_content.replace('LastSessionBody', 'MascotBody')
new_content = new_content.replace('Tu última sesión', 'Tu compañero')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Restructured tab_home.tscn successfully')
