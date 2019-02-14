<div class="copyright" >
  {% set current = date(Date.now(), "YYYY") %}
  &copy; {% if theme.since and theme.since != current %} {{ theme.since }} - {% endif %}
  <span itemprop="copyrightYear">{{ current }}</span>
  <span class="with-love">
    <i class="fa fa-{{ theme.authoricon }}"></i>
  </span>
  <span class="author" itemprop="copyrightHolder">{{ config.author }}</span>
</div>

{% if theme.copyright %}
<div class="powered-by">
  {{ __('footer.powered', '<a class="theme-link" href="https://root-wyj.github.io/">Mr.Jugg</a>') }}
</div>

<div class="theme-info">
  {{ __('footer.git') }} -
  <a class="theme-link" href="https://github.com/root-wyj">
    root-wyj
  </a>
</div>
{% endif %}
