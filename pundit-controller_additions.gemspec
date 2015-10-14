# coding: utf-8

Gem::Specification.new do |gem|
  gem.name        = 'pundit-controller_additions'
  gem.version     = '0.0.1'
  gem.authors     = ['Alex Coles']
  gem.email       = 'alex@alexbcolegem.com'
  gem.homepage    = 'https://github.com/qLearning/pundit-controller_additions'
  gem.summary     = 'CanCanCan Controller Additions made to work with Pundit.'
  gem.description = 'CanCanCan Controller Additions made to work with Pundit.'
  gem.platform    = Gem::Platform::RUBY
  gem.license     = 'MIT'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.required_ruby_version = Gem::Requirement.new('>= 2.1.0')

  gem.add_development_dependency 'bundler', '~> 1.3'
  gem.add_development_dependency 'rake', '~> 10.1.1'

  gem.add_dependency 'pundit', '~> 1.0'

  gem.rubyforge_project = gem.name
end
