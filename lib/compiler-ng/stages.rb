module Rubinius
  class CompilerNG
    Stages = { }

    class Stage
      attr_accessor :next_stage

      def self.stage(name)
        @stage = name
        Stages[name] = self
      end

      def self.stage_name
        @stage
      end

      def self.next_stage(klass)
        @next_stage_class = klass
      end

      def self.next_stage_class
        @next_stage_class
      end

      def initialize(compiler, last)
        @next_stage = create_next_stage compiler, last
      end

      def input(data)
        @input = data
      end

      def processor(klass)
        @processor = klass
      end

      def create_next_stage(compiler, last)
        return if self.class.stage_name == last

        stage = self.class.next_stage_class
        stage.new compiler, last if stage
      end

      def run_next
        if @next_stage
          @next_stage.input @output
          @next_stage.run
        else
          @output
        end
      end
    end

    # compiled method -> compiled file
    class Writer < Stage
      stage :compiled_file

      attr_accessor :name

      def initialize(compiler, last)
        super
        compiler.writer = self
        @processor = Rubinius::CompiledFile
      end

      def run
        @name = "#{@input.file}c" unless @name
        @processor.dump @input, @name
        @input
      end
    end

    # encoded bytecode -> compiled method
    class Packager < Stage
      stage :compiled_method
      next_stage Writer

      def initialize(compiler, last)
        super
        compiler.packager = self
      end

      def run
        @output = @input.package Rubinius::CompiledMethod
        run_next
      end
    end

    # symbolic bytecode -> encoded bytecode
    class Encoder < Stage
      stage :encoded_bytecode
      next_stage Packager

      def initialize(compiler, last)
        super
        compiler.encoder = self
        @encoder = InstructionSequence::Encoder
        @calculator = Compiler::StackDepthCalculator
      end

      def processor(encoder, calculator)
        @encoder = encoder
        @calculator = calculator
      end

      def run
        @input.encode @encoder, @calculator
        @output = @input
        run_next
      end
    end

    # AST -> symbolic bytecode
    class Generator < Stage
      stage :bytecode
      next_stage Encoder

      def initialize(compiler, last)
        super
        compiler.generator = self
        @processor = Rubinius::Generator
      end

      def run
        @output = @processor.new
        @input.bytecode @output
        @output.close
        run_next
      end
    end

    # source -> AST
    class Parser < Stage
      attr_accessor :transforms

      def initialize(compiler, last)
        super
        compiler.parser = self
        @transforms = []
        @processor = Rubinius::Melbourne
      end

      def root(klass)
        @root = klass
      end

      def default_transforms
        @transforms.concat AST::Transforms.default
      end

      def enable_transform(name)
        transform = AST::Transforms[name]
        @transforms << transform if transform
      end

      def run
        @output = @root.new parse
        @output.file = @file
        run_next
      end
    end

    # source file -> AST
    class FileParser < Parser
      stage :file
      next_stage Generator

      def input(file, line=1)
        @file = file
        @line = line
      end

      def parse
        @processor.new(@file, @line, @transforms).parse_file
      end
    end

    # source string -> AST
    class StringParser < Parser
      stage :string
      next_stage Generator

      def input(string, name="(eval)", line=1)
        @input = string
        @file = name
        @line = line
      end

      def parse
        @processor.new(@file, @line, @transforms).parse_string(@input)
      end
    end
  end
end