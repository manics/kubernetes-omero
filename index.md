## Stable releases

{% for chartmap in site.data.index.entries -%}
- [{{ chartmap[0] }}](#{{ chartmap[0] | slugify }})
{% endfor %}

{% for chartmap in site.data.index.entries %}
### {{ chartmap[0] }}

| | Version | Date | Application version |
|-|---------|------|---------------------|
  {% assign sortedcharts = chartmap[1] | sort: 'created' | reverse -%}
  {% for chart in sortedcharts -%}
| {% if forloop.first %}[![{{ chart.name }} icon]({{ chart.icon }}){:style="height:1.5em;vertical-align:middle"}]({{ chart.urls[0] }}){% endif %} | [{{ chart.name }} {{ chart.version }}]({{ chart.urls[0] }}) | {{ chart.created | date_to_rfc822 }} | {{ chart.appVersion }} |
  {% endfor %}
{% endfor %}
