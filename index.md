## Stable releases

{% for chartmap in site.data.index.entries -%}
- [{{ chartmap[0] }}](#{{ chartmap[0] | slugify }})
{% endfor %}

{% for chartmap in site.data.index.entries %}
### {{ chartmap[0] }}

| Version | Date |
|---------|------|
  {% assign sortedcharts = chartmap[1] | sort: 'created' | reverse -%}
  {% for chart in sortedcharts -%}
| [{{ chart.name }}-{{ chart.version }}]({{ chart.urls[0] }}) | {{ chart.created | date_to_rfc822 }} |
  {% endfor %}
{% endfor %}
