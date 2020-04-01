# -*- coding: utf-8 -*-

require "utils/ArithmeticEvaluator"
require "utils/normalizer"
require "utils/add_dice/node"

class AddDice
  class Parser
    def initialize(expr)
      @expr = expr
      @idx = 0
      @error = false
    end

    def parse()
      lhs, cmp_op, rhs = @expr.partition(/[<>=]+/)

      cmp_op = Normalizer.comparison_op(cmp_op)
      if !rhs.empty? && rhs != "?"
        rhs = ArithmeticEvaluator.new.eval(rhs)
      end

      @tokens = tokenize(lhs)
      lhs = expr()

      if @idx != @tokens.size
        @error = true
      end

      return AddDice::Node::Command.new(lhs, cmp_op, rhs)
    end

    def error?
      @error
    end

    private

    def tokenize(expr)
      expr.gsub(%r{[\+\-\*/DURS@]}) { |e| " #{e} " }.split(' ')
    end

    def expr
      consume("S")

      return add()
    end

    def add
      sequence = [mul()]

      loop do
        if consume("+")
          sequence.push(:+, nil, mul())
        elsif consume("-")
          sequence.push(:-, nil, mul())
        else
          break
        end
      end

      sequence = fold_sequence(sequence)
      return construct_binop(sequence)
    end

    def mul
      sequence = [unary()]

      loop do
        if consume("*")
          sequence.push(:*, nil, unary())
        elsif consume("/")
          rhs = unary()
          round_type = consume_round_type()
          sequence.push(:/, round_type, rhs)
        else
          break
        end
      end

      sequence = fold_sequence(sequence)
      return construct_binop(sequence)
    end

    def fold_sequence(sequence)
      list = [sequence.shift]

      while !sequence.empty?
        lhs = list.pop
        op, round_type, rhs = sequence.shift(3)

        if lhs.is_a?(Node::Number) && rhs.is_a?(Node::Number) && (list.empty? || op != :/)
          num = calc(lhs.literal, op, rhs.literal, round_type)
          list.push(Node::Number.new(num))
        else
          list.push(lhs, op, round_type, rhs)
        end
      end

      list
    end

    def construct_binop(sequence)
      node = sequence.shift

      while !sequence.empty?
        op, round_type, rhs = sequence.shift(3)
        if rhs.is_a?(Node::Number) && rhs.literal < 0
          if op == :+
            op = :-
            rhs = rhs.negate
          elsif op == :-
            op = :+
            rhs = rhs.negate
          end
        end
        node = Node::BinaryOp.new(node, op, rhs, round_type)
      end

      node
    end

    def calc(lhs, op, rhs, round_type)
      if op != :/
        return lhs.send(op, rhs)
      end

      if rhs.zero?
        @error = true
        return 1
      end

      case round_type
      when :roundUp
        (lhs.to_f / rhs).ceil
      when :roundOff
        (lhs.to_f / rhs).round
      else
        lhs / rhs
      end
    end

    def unary
      if consume("+")
        unary()
      elsif consume("-")
        node = unary()

        case node
        when Node::Negate
          node.body
        when Node::Number
          node.negate()
        else
          AddDice::Node::Negate.new(node)
        end
      else
        term()
      end
    end

    def term
      ret = expect_number()
      if consume("D")
        times = ret
        sides = expect_number()
        critical = consume("@") ? expect_number() : nil

        ret = AddDice::Node::DiceRoll.new(times, sides, critical)
      end

      ret
    end

    def consume(str)
      if @tokens[@idx] != str
        return false
      end

      @idx += 1
      return true
    end

    def consume_round_type()
      if consume("U")
        :roundUp
      elsif consume("R")
        :roundOff
      end
    end

    def expect(str)
      if @tokens[@idx] != str
        @error = true
      end

      @idx += 1
    end

    def expect_number()
      unless integer?(@tokens[@idx])
        @error = true
        @idx += 1
        return AddDice::Node::Number.new(0)
      end

      ret = @tokens[@idx].to_i
      @idx += 1
      return AddDice::Node::Number.new(ret)
    end

    def integer?(str)
      # Ruby 1.9 以降では Kernel.#Integer を使うべき
      # Ruby 1.8 にもあるが、基数を指定できない問題がある
      !/^\d+$/.match(str).nil?
    end
  end
end
