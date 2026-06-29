insert into public.styles (id, name, prompt_template, sample_image_path) values
('souvenir','Travel Postcard',
'Please use the real photo I provide to create a matching travel poster image divided into two sections (top and bottom), in a "city check-in/ fridge magnet souvenir" style.
[Layout Structure]
*   Top section: minimalist solid-color background.
*   Bottom section: keep the original photo completely unchanged.
[Top Section: Fridge Magnet Icon]
Extract the most recognizable subject element from the original photo in the bottom section:
1.    Preserve the original outlines, colors, and recognizable characteristics;
2.    Design it like a travel souvenir fridge magnet;
3.    Sharp edges with a metallic border;
4.    Place the icon in the center;
5.    Keep the icon relatively small with plenty of negative space around it.
[Background Color]
Use a solid background color for the top section, based on the dominant color from the original image.
[Overall Style]
The overall result should look like a travel photo card / souvenir postcard.',
'samples/souvenir.png'),
('palmreading','Palm Reading',
'Based on my hand, create a complete palm reading guide. Analyse the palm in detail and present the reading in a clean, minimal, luxury editorial style. Use thin lines, rounded cards, elegant spacing, and an expensive high-end aesthetic. Keep the focus on the palm reading itself.',
'samples/palmreading.png')
on conflict (id) do nothing;
